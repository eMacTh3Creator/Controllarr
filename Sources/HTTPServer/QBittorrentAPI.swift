//
//  QBittorrentAPI.swift
//  Controllarr — Phase 1
//
//  Install handlers that mimic qBittorrent's Web API v2 well enough to let
//  Sonarr, Radarr, and Overseerr talk to Controllarr as if it were a qBit
//  instance. We do not aim for bit-for-bit fidelity — just the endpoints
//  the *arr apps actually call and the shape they expect.
//
//  Auth is deliberately minimal. We accept the configured username +
//  password, hand out a session cookie, and leave cookie storage in a
//  process-local actor. Good enough for a single-user app bound to
//  localhost. Hardening lives in Phase 6.
//

import Foundation
import Hummingbird
import NIOCore
import TorrentEngine
import Persistence

public enum QBittorrentAPI {

    /// Version strings Sonarr/Radarr compare against. Bump if we
    /// implement enough v2.10+ surface to claim it.
    static let qbittorrentVersion = "v4.6.0"
    static let webAPIVersion      = "2.9.3"

    public static func install(on router: Router<BasicRequestContext>, services: HTTPServer.Services) {
        let sessions = SessionStore()

        // MARK: /auth

        router.post("/api/v2/auth/login") { request, _ -> Response in
            let body = try await request.body.collect(upTo: 64 * 1024)
            let form = FormParser.parse(body)
            let username = form["username"] ?? ""
            let password = form["password"] ?? ""
            let settings = await services.store.settings()
            if username == settings.webUIUsername && password == settings.webUIPassword {
                let sid = await sessions.issue()
                var headers = HTTPFields()
                headers[.setCookie] = "SID=\(sid); Path=/; HttpOnly"
                return Response(
                    status: .ok,
                    headers: headers,
                    body: .init(byteBuffer: ByteBuffer(string: "Ok."))
                )
            }
            return Response(
                status: .forbidden,
                body: .init(byteBuffer: ByteBuffer(string: "Fails."))
            )
        }

        router.post("/api/v2/auth/logout") { _, _ -> Response in
            return Response(status: .ok)
        }

        // MARK: /app

        router.get("/api/v2/app/version") { _, _ -> Response in
            plainText(qbittorrentVersion)
        }
        router.get("/api/v2/app/webapiVersion") { _, _ -> Response in
            plainText(webAPIVersion)
        }
        router.get("/api/v2/app/buildInfo") { _, _ -> Response in
            json([
                "qt": "6.5.0",
                "libtorrent": "2.0.12",
                "boost": "1.83.0",
                "openssl": "3.0",
                "bitness": 64
            ] as [String: Any])
        }
        router.get("/api/v2/app/preferences") { _, _ -> Response in
            let s = await services.store.settings()
            let session = await services.engine.sessionStats()
            return json(Preferences.from(settings: s, listenPort: Int(session.listenPort)).asDictionary)
        }
        router.post("/api/v2/app/setPreferences") { request, _ -> Response in
            let body = try await request.body.collect(upTo: 256 * 1024)
            let form = FormParser.parse(body)
            guard let jsonString = form["json"],
                  let data = jsonString.data(using: .utf8),
                  let dict = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                return Response(status: .badRequest)
            }
            await services.store.updateSettings { s in
                if let save = dict["save_path"] as? String { s.defaultSavePath = save }
                if let user = dict["web_ui_username"] as? String { s.webUIUsername = user }
                if let pwd  = dict["web_ui_password"] as? String, !pwd.isEmpty { s.webUIPassword = pwd }
                if let port = dict["listen_port"] as? Int {
                    Task { await services.engine.setListenPort(UInt16(port)) }
                }
            }
            return Response(status: .ok)
        }

        // MARK: /torrents/info

        router.get("/api/v2/torrents/info") { request, _ -> Response in
            let query = FormParser.parseQuery(request.uri.query ?? "")
            let filter = query["filter"] ?? "all"
            let categoryFilter = query["category"]
            let hashesFilter: Set<String>? = query["hashes"].map {
                Set($0.split(separator: "|").map(String.init))
            }

            let all = await services.engine.pollStats()
            let categories = await services.store.snapshot().categoryByHash

            let filtered = all.filter { t in
                if let hashesFilter, !hashesFilter.contains(t.infoHash) { return false }
                if let categoryFilter, categoryFilter != "", t.category != categoryFilter && categories[t.infoHash] != categoryFilter {
                    return false
                }
                switch filter {
                case "downloading":
                    return t.state == .downloading || t.state == .downloadingMetadata
                case "seeding":
                    return t.state == .seeding
                case "completed":
                    return t.state == .finished || t.state == .seeding
                case "paused":
                    return t.paused
                case "active":
                    return t.downloadRate > 0 || t.uploadRate > 0
                case "inactive":
                    return t.downloadRate == 0 && t.uploadRate == 0
                default:
                    return true
                }
            }

            let out = filtered.map { QBTorrentInfo.from($0, categoryOverlay: categories) }
            return json(out.map(\.asDictionary))
        }

        router.get("/api/v2/torrents/properties") { request, _ -> Response in
            let query = FormParser.parseQuery(request.uri.query ?? "")
            guard let hash = query["hash"],
                  let t = await services.engine.stats(for: hash) else {
                return Response(status: .notFound)
            }
            return json(QBTorrentProperties.from(t).asDictionary)
        }

        // MARK: /torrents/add

        router.post("/api/v2/torrents/add") { request, _ -> Response in
            let contentType = request.headers[.contentType] ?? ""
            let body = try await request.body.collect(upTo: 10 * 1024 * 1024)

            var urls: [String] = []
            var category: String? = nil
            var savePath: String? = nil
            var paused: Bool = false
            var torrentFileBlobs: [(filename: String, data: Data)] = []

            if contentType.contains("multipart/form-data") {
                let parts = MultipartParser.parse(body: body, contentType: contentType)
                for p in parts {
                    switch p.name {
                    case "urls":
                        let text = String(decoding: p.body, as: UTF8.self)
                        urls.append(contentsOf: text
                            .split(whereSeparator: { $0 == "\n" || $0 == "\r" })
                            .map(String.init)
                            .filter { !$0.isEmpty })
                    case "category":  category = String(decoding: p.body, as: UTF8.self)
                    case "savepath":  savePath = String(decoding: p.body, as: UTF8.self)
                    case "paused":
                        paused = String(decoding: p.body, as: UTF8.self).lowercased() == "true"
                    case "torrents":
                        torrentFileBlobs.append((p.filename ?? "upload.torrent", Data(p.body)))
                    default: break
                    }
                }
            } else {
                // application/x-www-form-urlencoded fallback.
                let form = FormParser.parse(body)
                if let u = form["urls"] {
                    urls = u.split(whereSeparator: { $0 == "\n" || $0 == "\r" })
                        .map(String.init).filter { !$0.isEmpty }
                }
                category = form["category"]
                savePath = form["savepath"]
                paused = (form["paused"]?.lowercased() == "true")
            }

            var addedHashes: [String] = []
            for u in urls {
                do {
                    let h = try await services.engine.addMagnet(u, category: category)
                    if !h.isEmpty { addedHashes.append(h) }
                    if let category { await services.store.noteCategoryForHash(h, category: category) }
                } catch {
                    NSLog("[Controllarr] addMagnet failed: \(error)")
                }
            }
            for blob in torrentFileBlobs {
                let tmp = URL(fileURLWithPath: NSTemporaryDirectory())
                    .appendingPathComponent("ctrl-\(UUID().uuidString).torrent")
                try? blob.data.write(to: tmp)
                do {
                    let h = try await services.engine.addTorrentFile(at: tmp, category: category)
                    if !h.isEmpty { addedHashes.append(h) }
                    if let category { await services.store.noteCategoryForHash(h, category: category) }
                } catch {
                    NSLog("[Controllarr] addTorrentFile failed: \(error)")
                }
                try? FileManager.default.removeItem(at: tmp)
            }

            if paused {
                for h in addedHashes { _ = await services.engine.pause(infoHash: h) }
            }
            _ = savePath // save path per-torrent override not yet wired through the shim
            return plainText("Ok.")
        }

        // MARK: /torrents/pause|resume|delete

        router.post("/api/v2/torrents/pause") { request, _ -> Response in
            let form = FormParser.parse(try await request.body.collect(upTo: 64 * 1024))
            for h in hashList(from: form["hashes"]) {
                _ = await services.engine.pause(infoHash: h)
            }
            return plainText("")
        }
        router.post("/api/v2/torrents/resume") { request, _ -> Response in
            let form = FormParser.parse(try await request.body.collect(upTo: 64 * 1024))
            for h in hashList(from: form["hashes"]) {
                _ = await services.engine.resume(infoHash: h)
            }
            return plainText("")
        }
        router.post("/api/v2/torrents/delete") { request, _ -> Response in
            let form = FormParser.parse(try await request.body.collect(upTo: 64 * 1024))
            let deleteFiles = (form["deleteFiles"]?.lowercased() == "true")
            for h in hashList(from: form["hashes"]) {
                _ = await services.engine.remove(infoHash: h, deleteFiles: deleteFiles)
                await services.store.noteCategoryForHash(h, category: nil)
            }
            return plainText("")
        }

        // MARK: /torrents/categories

        router.get("/api/v2/torrents/categories") { _, _ -> Response in
            let cats = await services.store.categories()
            var out: [String: [String: String]] = [:]
            for c in cats {
                out[c.name] = ["name": c.name, "savePath": c.savePath]
            }
            return json(out)
        }
        router.post("/api/v2/torrents/createCategory") { request, _ -> Response in
            let form = FormParser.parse(try await request.body.collect(upTo: 64 * 1024))
            guard let name = form["category"], !name.isEmpty else {
                return Response(status: .badRequest)
            }
            let save = form["savePath"] ?? ""
            await services.store.upsertCategory(
                Category(name: name, savePath: save)
            )
            return plainText("")
        }
        router.post("/api/v2/torrents/removeCategories") { request, _ -> Response in
            let form = FormParser.parse(try await request.body.collect(upTo: 64 * 1024))
            for name in (form["categories"] ?? "")
                .split(whereSeparator: { $0 == "\n" || $0 == "\r" })
                .map(String.init) {
                await services.store.removeCategory(named: name)
            }
            return plainText("")
        }
        router.post("/api/v2/torrents/setCategory") { request, _ -> Response in
            let form = FormParser.parse(try await request.body.collect(upTo: 64 * 1024))
            let category = form["category"]
            for h in hashList(from: form["hashes"]) {
                await services.engine.setCategory(category, for: h)
                await services.store.noteCategoryForHash(h, category: category)
            }
            return plainText("")
        }

        // MARK: Controllarr-native endpoints

        router.get("/api/controllarr/stats") { _, _ -> Response in
            let s = await services.engine.sessionStats()
            return json([
                "downloadRate": s.downloadRate,
                "uploadRate":   s.uploadRate,
                "totalDownloaded": s.totalDownloaded,
                "totalUploaded":   s.totalUploaded,
                "numTorrents":     s.numTorrents,
                "numPeers":        s.numPeersConnected,
                "hasIncoming":     s.hasIncomingConnections,
                "listenPort":      Int(s.listenPort)
            ] as [String: Any])
        }
        router.post("/api/controllarr/port/cycle") { _, _ -> Response in
            await services.forceCyclePort()
            return plainText("cycling")
        }
    }

    // MARK: - Utilities

    static func hashList(from raw: String?) -> [String] {
        guard let raw else { return [] }
        return raw.split(separator: "|").map(String.init).filter { !$0.isEmpty }
    }

    static func plainText(_ s: String) -> Response {
        var headers = HTTPFields()
        headers[.contentType] = "text/plain; charset=utf-8"
        return Response(status: .ok, headers: headers, body: .init(byteBuffer: ByteBuffer(string: s)))
    }

    static func json(_ value: Any) -> Response {
        let data = (try? JSONSerialization.data(withJSONObject: value, options: [])) ?? Data("{}".utf8)
        var headers = HTTPFields()
        headers[.contentType] = "application/json"
        return Response(status: .ok, headers: headers, body: .init(byteBuffer: ByteBuffer(bytes: data)))
    }
}

// MARK: - Session store

actor SessionStore {
    private var tokens: Set<String> = []
    func issue() -> String {
        let sid = UUID().uuidString.replacingOccurrences(of: "-", with: "")
        tokens.insert(sid)
        return sid
    }
    func valid(_ sid: String) -> Bool { tokens.contains(sid) }
}
