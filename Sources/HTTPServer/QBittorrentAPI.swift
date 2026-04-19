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
import Services

public enum QBittorrentAPI {

    /// Version strings Sonarr/Radarr compare against. Bump if we
    /// implement enough v2.10+ surface to claim it.
    static let qbittorrentVersion = "v4.6.0"
    static let webAPIVersion      = "2.9.3"

    @discardableResult
    public static func install(on router: Router<BasicRequestContext>, services: HTTPServer.Services) -> SessionStore {
        let sessions = SessionStore()

        // MARK: /auth

        router.post("/api/v2/auth/login") { request, _ -> Response in
            let body = try await request.body.collect(upTo: 64 * 1024)
            let form = FormParser.parse(body)
            let username = form["username"] ?? ""
            let password = form["password"] ?? ""
            let settings = await services.store.settings()
            let resolvedPassword = await services.store.resolvedWebUIPassword()
            if username == settings.webUIUsername && password == resolvedPassword {
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

        router.post("/api/v2/auth/logout") { request, _ -> Response in
            if let sid = Self.extractSID(from: request) {
                await sessions.revoke(sid)
            }
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
            if let pwd = dict["web_ui_password"] as? String, !pwd.isEmpty {
                await services.store.setWebUIPassword(pwd)
            }
            await services.store.updateSettings { s in
                if let save = dict["save_path"] as? String { s.defaultSavePath = save }
                if let user = dict["web_ui_username"] as? String { s.webUIUsername = user }
                if let port = dict["listen_port"] as? Int {
                    Task { await services.engine.setListenPort(UInt16(port)) }
                }
            }
            return Response(status: .ok)
        }

        // MARK: /transfer

        router.get("/api/v2/transfer/info") { _, _ -> Response in
            let s = await services.engine.sessionStats()
            return json([
                "dl_info_speed": s.downloadRate,
                "dl_info_data": s.totalDownloaded,
                "up_info_speed": s.uploadRate,
                "up_info_data": s.totalUploaded,
                "dl_rate_limit": 0,
                "up_rate_limit": 0,
                "dht_nodes": 0,
                "connection_status": s.hasIncomingConnections ? "connected" : "firewalled",
            ] as [String: Any])
        }
        router.get("/api/v2/transfer/speedLimitsMode") { _, _ -> Response in
            plainText("0")
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

            // Normalize empty savepath to nil.
            let explicitPath = savePath?.isEmpty == false ? savePath : nil

            // Resolve the active duplicate-policy from persistence, then
            // dispatch every incoming add through the duplicate-aware
            // engine path so re-adds from Sonarr/Radarr don't error.
            // Non-interactive (ask -> mergeTrackers fallback) since there
            // is no operator at the other end of an API call.
            let settings = await services.store.settings()
            let mode: DuplicatePolicyMode = {
                switch settings.duplicateTorrentPolicy {
                case .ignore:        return .ignore
                case .mergeTrackers: return .mergeTrackers
                case .ask:           return .ask
                }
            }()

            var addedHashes: [String] = []
            for u in urls {
                do {
                    let result = try await services.engine.addMagnet(
                        u,
                        category: category,
                        explicitSavePath: explicitPath,
                        policy: mode,
                        interactive: false
                    )
                    let h = result.infoHash
                    // Always emit the hash so the caller can reference
                    // the torrent — whether we just added it or merged
                    // trackers into an existing one.
                    if !h.isEmpty { addedHashes.append(h) }
                    // Only set the category for *new* adds. Don't
                    // stomp an existing categorization when a duplicate
                    // add arrives with (or without) a category argument.
                    if case .added = result, let category {
                        await services.store.noteCategoryForHash(h, category: category)
                    }
                } catch {
                    NSLog("[Controllarr] addMagnet failed: \(error)")
                }
            }
            for blob in torrentFileBlobs {
                let tmp = URL(fileURLWithPath: NSTemporaryDirectory())
                    .appendingPathComponent("ctrl-\(UUID().uuidString).torrent")
                try? blob.data.write(to: tmp)
                do {
                    let result = try await services.engine.addTorrentFile(
                        at: tmp,
                        category: category,
                        explicitSavePath: explicitPath,
                        policy: mode,
                        interactive: false
                    )
                    let h = result.infoHash
                    if !h.isEmpty { addedHashes.append(h) }
                    if case .added = result, let category {
                        await services.store.noteCategoryForHash(h, category: category)
                    }
                } catch {
                    NSLog("[Controllarr] addTorrentFile failed: \(error)")
                }
                try? FileManager.default.removeItem(at: tmp)
            }

            if paused {
                for h in addedHashes { _ = await services.engine.pause(infoHash: h) }
            }
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
        // qBittorrent's "Force Resume" / "Force Start" — `value=true`
        // takes a torrent out of the auto-managed pool so libtorrent's
        // queue system cannot silently re-pause it; `value=false` puts it
        // back into the queue (equivalent to a normal resume).
        router.post("/api/v2/torrents/setForceStart") { request, _ -> Response in
            let form = FormParser.parse(try await request.body.collect(upTo: 64 * 1024))
            let force = (form["value"]?.lowercased() == "true")
            for h in hashList(from: form["hashes"]) {
                if force {
                    _ = await services.engine.forceResume(infoHash: h)
                } else {
                    _ = await services.engine.resume(infoHash: h)
                }
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
            // Preserve any existing Controllarr-specific fields if the
            // category already exists (Sonarr/Radarr will call this to
            // "make sure" a category exists before adding).
            if let existing = await services.store.category(named: name) {
                var updated = existing
                if !save.isEmpty { updated.savePath = save }
                await services.store.upsertCategory(updated)
            } else {
                await services.store.upsertCategory(
                    Category(name: name, savePath: save)
                )
            }
            return plainText("")
        }
        router.post("/api/v2/torrents/editCategory") { request, _ -> Response in
            let form = FormParser.parse(try await request.body.collect(upTo: 64 * 1024))
            guard let name = form["category"], !name.isEmpty else {
                return Response(status: .badRequest)
            }
            let save = form["savePath"] ?? ""
            // Honor an optional `moveFiles` form override — falls back to the
            // persisted `categoryChangeMove` policy (ask/always/never).
            let settings = await services.store.settings()
            let existing = await services.store.category(named: name)
            let pathChanged = (existing?.savePath ?? "") != save && !save.isEmpty
            let override = form["moveFiles"].map { $0.lowercased() == "true" }
            let shouldMove: Bool = {
                if let override { return override }
                switch settings.categoryChangeMove {
                case .always: return pathChanged
                case .never:  return false
                case .ask:    return false      // API default when unspecified
                }
            }()
            if let existing {
                var updated = existing
                updated.savePath = save
                await services.store.upsertCategory(updated)
            }
            if pathChanged && shouldMove {
                _ = await services.engine.moveCategoryMembers(name, to: save)
            }
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
            // Honor optional per-request `moveFiles` form field; otherwise
            // defer to the persisted `categoryChangeMove` policy.
            let settings = await services.store.settings()
            let override = form["moveFiles"].map { $0.lowercased() == "true" }
            let shouldMove: Bool = {
                if let override { return override }
                switch settings.categoryChangeMove {
                case .always: return true
                case .never:  return false
                case .ask:    return false      // WebAPI default when unspecified
                }
            }()
            for h in hashList(from: form["hashes"]) {
                _ = await services.engine.setCategory(
                    category,
                    for: h,
                    moveFiles: shouldMove
                )
                await services.store.noteCategoryForHash(h, category: category)
            }
            return plainText("")
        }

        // MARK: /torrents/files, trackers, pieceStates (qBit compat)

        router.get("/api/v2/torrents/files") { request, _ -> Response in
            let query = FormParser.parseQuery(request.uri.query ?? "")
            guard let hash = query["hash"],
                  let files = await services.engine.fileInfo(for: hash) else {
                return Response(status: .notFound)
            }
            let out: [[String: Any]] = files.map { f in
                [
                    "index": f.index,
                    "name": f.name,
                    "size": f.size,
                    "progress": f.priority == 0 ? 0.0 : 1.0,
                    "priority": f.priority,
                    "is_seed": false,
                    "piece_range": [0, 0],
                    "availability": -1,
                ]
            }
            return json(out)
        }
        router.get("/api/v2/torrents/trackers") { request, _ -> Response in
            let query = FormParser.parseQuery(request.uri.query ?? "")
            guard let hash = query["hash"],
                  let trackers = await services.engine.trackers(for: hash) else {
                return Response(status: .notFound)
            }
            let out: [[String: Any]] = trackers.map { t in
                [
                    "url": t.url,
                    "status": t.status,
                    "tier": t.tier,
                    "num_peers": t.numPeers,
                    "num_seeds": t.numSeeds,
                    "num_leeches": t.numLeechers,
                    "num_downloaded": t.numDownloaded,
                    "msg": t.message,
                ]
            }
            return json(out)
        }
        router.get("/api/v2/torrents/pieceStates") { request, _ -> Response in
            let query = FormParser.parseQuery(request.uri.query ?? "")
            guard let _ = query["hash"] else {
                return Response(status: .notFound)
            }
            return json([] as [Any])
        }

        // MARK: Controllarr: files, trackers, peers

        router.get("/api/controllarr/torrents/:hash/files") { _, context -> Response in
            guard let hash = context.parameters.get("hash"),
                  let files = await services.engine.fileInfo(for: hash) else {
                return Response(status: .notFound)
            }
            let out: [[String: Any]] = files.map { f in
                [
                    "index": f.index,
                    "name": f.name,
                    "size": f.size,
                    "priority": f.priority,
                ]
            }
            return json(out)
        }
        router.post("/api/controllarr/torrents/:hash/files") { request, context -> Response in
            guard let hash = context.parameters.get("hash") else {
                return Response(status: .badRequest)
            }
            let body = try await request.body.collect(upTo: 256 * 1024)
            guard let dict = try? JSONSerialization.jsonObject(with: Data(buffer: body))
                    as? [String: Any],
                  let priorities = dict["priorities"] as? [Int] else {
                return Response(status: .badRequest)
            }
            let ok = await services.engine.setFilePriorities(priorities, for: hash)
            return ok ? plainText("Ok.") : Response(status: .conflict)
        }
        router.get("/api/controllarr/torrents/:hash/trackers") { _, context -> Response in
            guard let hash = context.parameters.get("hash"),
                  let trackers = await services.engine.trackers(for: hash) else {
                return Response(status: .notFound)
            }
            let out: [[String: Any]] = trackers.map { t in
                [
                    "url": t.url,
                    "tier": t.tier,
                    "numPeers": t.numPeers,
                    "numSeeds": t.numSeeds,
                    "numLeechers": t.numLeechers,
                    "numDownloaded": t.numDownloaded,
                    "message": t.message,
                    "status": t.status,
                ]
            }
            return json(out)
        }
        router.get("/api/controllarr/torrents/:hash/peers") { _, context -> Response in
            guard let hash = context.parameters.get("hash"),
                  let peers = await services.engine.peers(for: hash) else {
                return Response(status: .notFound)
            }
            let out: [[String: Any]] = peers.map { p in
                [
                    "ip": p.ip,
                    "port": p.port,
                    "client": p.client,
                    "progress": p.progress,
                    "downloadRate": p.downloadRate,
                    "uploadRate": p.uploadRate,
                    "totalDownload": p.totalDownload,
                    "totalUpload": p.totalUpload,
                    "flags": p.flags,
                    "country": p.country,
                ]
            }
            return json(out)
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

        // MARK: Controllarr: categories (extended schema)

        router.get("/api/controllarr/categories") { _, _ -> Response in
            let cats = await services.store.categories()
            return json(cats.map(categoryDict))
        }
        router.post("/api/controllarr/categories") { request, _ -> Response in
            let body = try await request.body.collect(upTo: 64 * 1024)
            guard let dict = try? JSONSerialization.jsonObject(with: Data(buffer: body))
                    as? [String: Any],
                  let name = dict["name"] as? String, !name.isEmpty,
                  let save = dict["savePath"] as? String
            else { return Response(status: .badRequest) }

            let category = Category(
                name: name,
                savePath: save,
                completePath: (dict["completePath"] as? String).flatMap { $0.isEmpty ? nil : $0 },
                extractArchives: (dict["extractArchives"] as? Bool) ?? false,
                blockedExtensions: (dict["blockedExtensions"] as? [String]) ?? [],
                maxRatio: dict["maxRatio"] as? Double,
                maxSeedingTimeMinutes: dict["maxSeedingTimeMinutes"] as? Int
            )
            await services.store.upsertCategory(category)
            await services.engine.registerBlockedExtensions(
                category.blockedExtensions,
                forCategory: category.name
            )
            return json(categoryDict(category))
        }
        router.delete("/api/controllarr/categories/:name") { request, context -> Response in
            guard let name = context.parameters.get("name") else {
                return Response(status: .badRequest)
            }
            await services.store.removeCategory(named: name)
            return plainText("")
        }

        // MARK: Controllarr: settings (full schema)

        router.get("/api/controllarr/settings") { _, _ -> Response in
            let s = await services.store.settings()
            return json(settingsDict(s))
        }
        router.post("/api/controllarr/settings") { request, _ -> Response in
            let body = try await request.body.collect(upTo: 64 * 1024)
            guard let dict = try? JSONSerialization.jsonObject(with: Data(buffer: body))
                    as? [String: Any] else {
                return Response(status: .badRequest)
            }
            // Handle password separately via Keychain
            if let v = dict["webUIPassword"] as? String, !v.isEmpty {
                await services.store.setWebUIPassword(v)
            }
            // Handle *arr API keys via Keychain
            if let endpoints = dict["arrEndpoints"] as? [[String: Any]] {
                for ep in endpoints {
                    if let name = ep["name"] as? String,
                       let key = ep["apiKey"] as? String, !key.isEmpty {
                        await services.store.setArrAPIKey(key, forEndpoint: name)
                    }
                }
            }
            await services.store.updateSettings { s in
                if let v = dict["listenPortRangeStart"] as? Int { s.listenPortRangeStart = UInt16(v) }
                if let v = dict["listenPortRangeEnd"]   as? Int { s.listenPortRangeEnd   = UInt16(v) }
                if let v = dict["stallThresholdMinutes"] as? Int { s.stallThresholdMinutes = v }
                if let v = dict["defaultSavePath"]   as? String { s.defaultSavePath = v }
                if let v = dict["webUIHost"]         as? String { s.webUIHost = v }
                if let v = dict["webUIPort"]         as? Int    { s.webUIPort = v }
                if let v = dict["webUIUsername"]     as? String { s.webUIUsername = v }
                if dict.keys.contains("globalMaxRatio") {
                    s.globalMaxRatio = dict["globalMaxRatio"] as? Double
                }
                if dict.keys.contains("globalMaxSeedingTimeMinutes") {
                    s.globalMaxSeedingTimeMinutes = dict["globalMaxSeedingTimeMinutes"] as? Int
                }
                if let v = dict["seedLimitAction"] as? String,
                   let action = SeedLimitAction(rawValue: v) {
                    s.seedLimitAction = action
                }
                if let v = dict["minimumSeedTimeMinutes"] as? Int { s.minimumSeedTimeMinutes = v }
                if let v = dict["healthStallMinutes"]     as? Int { s.healthStallMinutes = v }
                if let v = dict["healthReannounceOnStall"] as? Bool { s.healthReannounceOnStall = v }
                if let rules = dict["recoveryRules"] as? [[String: Any]] {
                    s.recoveryRules = rules.compactMap { rule in
                        guard let triggerRaw = rule["trigger"] as? String,
                              let trigger = RecoveryTrigger(rawValue: triggerRaw),
                              let actionRaw = rule["action"] as? String,
                              let action = RecoveryAction(rawValue: actionRaw) else {
                            return nil
                        }
                        return RecoveryRule(
                            enabled: (rule["enabled"] as? Bool) ?? false,
                            trigger: trigger,
                            action: action,
                            delayMinutes: (rule["delayMinutes"] as? Int) ?? 0
                        )
                    }
                }
                // Bandwidth schedule
                if let rules = dict["bandwidthSchedule"] as? [[String: Any]] {
                    s.bandwidthSchedule = rules.compactMap { r in
                        guard let name = r["name"] as? String else { return nil }
                        return BandwidthRule(
                            name: name,
                            enabled: (r["enabled"] as? Bool) ?? true,
                            daysOfWeek: (r["daysOfWeek"] as? [Int]) ?? [2,3,4,5,6],
                            startHour: (r["startHour"] as? Int) ?? 0,
                            startMinute: (r["startMinute"] as? Int) ?? 0,
                            endHour: (r["endHour"] as? Int) ?? 0,
                            endMinute: (r["endMinute"] as? Int) ?? 0,
                            maxDownloadKBps: r["maxDownloadKBps"] as? Int,
                            maxUploadKBps: r["maxUploadKBps"] as? Int
                        )
                    }
                }
                // VPN protection
                if let v = dict["vpnEnabled"] as? Bool { s.vpnEnabled = v }
                if let v = dict["vpnKillSwitch"] as? Bool { s.vpnKillSwitch = v }
                if let v = dict["vpnBindInterface"] as? Bool { s.vpnBindInterface = v }
                if let v = dict["vpnInterfacePrefix"] as? String { s.vpnInterfacePrefix = v }
                if let v = dict["vpnMonitorIntervalSeconds"] as? Int { s.vpnMonitorIntervalSeconds = v }
                if dict.keys.contains("diskSpaceMinimumGB") {
                    s.diskSpaceMinimumGB = dict["diskSpaceMinimumGB"] as? Int
                }
                if let v = dict["diskSpaceMonitorPath"] as? String { s.diskSpaceMonitorPath = v }
                if let v = dict["arrReSearchAfterHours"] as? Int { s.arrReSearchAfterHours = v }
                // Update arr endpoint metadata (not keys — handled above)
                if let endpoints = dict["arrEndpoints"] as? [[String: Any]] {
                    s.arrEndpoints = endpoints.compactMap { ep in
                        guard let name = ep["name"] as? String,
                              let kindStr = ep["kind"] as? String,
                              let kind = ArrEndpoint.Kind(rawValue: kindStr),
                              let url = ep["baseURL"] as? String else { return nil }
                        return ArrEndpoint(
                            name: name, kind: kind, baseURL: url,
                            apiKeyInKeychain: true, apiKey: ""
                        )
                    }
                }
            }
            return plainText("")
        }

        // MARK: Controllarr: backup / restore

        router.get("/api/controllarr/backup") { request, _ -> Response in
            let query = FormParser.parseQuery(request.uri.query ?? "")
            let includeSecrets = (query["includeSecrets"]?.lowercased() == "true")
            let archive = await services.store.exportBackup(includeSecrets: includeSecrets)
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            do {
                let data = try encoder.encode(archive)
                let formatter = ISO8601DateFormatter()
                let timestamp = formatter.string(from: archive.createdAt)
                    .replacingOccurrences(of: ":", with: "-")
                let filename = "controllarr-backup-\(timestamp).json"
                services.logger.info(
                    "backup",
                    "exported backup (\(includeSecrets ? "with" : "without") secrets)"
                )
                return jsonData(
                    data,
                    contentDisposition: "attachment; filename=\"\(filename)\""
                )
            } catch {
                services.logger.error("backup", "failed to encode backup: \(error.localizedDescription)")
                return Response(status: .internalServerError)
            }
        }
        router.post("/api/controllarr/backup/import") { request, _ -> Response in
            let body = try await request.body.collect(upTo: 10 * 1024 * 1024)
            let decoder = JSONDecoder()
            do {
                let archive = try decoder.decode(BackupArchive.self, from: Data(buffer: body))
                let result = try await services.store.restoreBackup(archive)
                services.logger.warn(
                    "backup",
                    "imported backup with \(result.categoryCount) categories and \(result.endpointCount) *arr endpoints"
                )
                return json([
                    "restoredAt": result.restoredAt.timeIntervalSince1970,
                    "categoryCount": result.categoryCount,
                    "endpointCount": result.endpointCount,
                    "includedSecrets": result.includedSecrets,
                    "restartRecommended": result.restartRecommended,
                ] as [String: Any])
            } catch let error as BackupError {
                services.logger.warn("backup", "backup import rejected: \(error.localizedDescription)")
                return Response(
                    status: .badRequest,
                    body: .init(byteBuffer: ByteBuffer(string: error.localizedDescription))
                )
            } catch {
                services.logger.warn("backup", "backup import failed: \(error.localizedDescription)")
                return Response(
                    status: .badRequest,
                    body: .init(byteBuffer: ByteBuffer(string: error.localizedDescription))
                )
            }
        }

        // MARK: Controllarr: health

        router.get("/api/controllarr/health") { _, _ -> Response in
            let issues = await services.healthMonitor.snapshot()
            let out: [[String: Any]] = issues.map { issue in
                [
                    "infoHash": issue.infoHash,
                    "name": issue.name,
                    "reason": issue.reason.rawValue,
                    "firstSeen": issue.firstSeen.timeIntervalSince1970,
                    "lastProgress": issue.lastProgress,
                    "lastUpdated": issue.lastUpdated.timeIntervalSince1970,
                ]
            }
            return json(out)
        }
        router.post("/api/controllarr/health/clear") { request, _ -> Response in
            let form = FormParser.parse(try await request.body.collect(upTo: 64 * 1024))
            if let hash = form["hash"] {
                await services.healthMonitor.clearIssue(hash: hash)
            }
            return plainText("")
        }

        // MARK: Controllarr: recovery center

        router.get("/api/controllarr/recovery") { _, _ -> Response in
            let records = await services.recoveryCenter.snapshot()
            let out: [[String: Any]] = records.map { record in
                [
                    "infoHash": record.infoHash,
                    "name": record.name,
                    "reason": record.reason.rawValue,
                    "action": record.action.rawValue,
                    "source": record.source.rawValue,
                    "success": record.success,
                    "message": record.message,
                    "timestamp": record.timestamp.timeIntervalSince1970,
                ]
            }
            return json(out)
        }
        router.post("/api/controllarr/recovery/run") { request, _ -> Response in
            let form = FormParser.parse(try await request.body.collect(upTo: 64 * 1024))
            guard let hash = form["hash"], !hash.isEmpty else {
                return Response(status: .badRequest)
            }
            let overrideAction = form["action"].flatMap { RecoveryAction(rawValue: $0) }
            do {
                let record = try await services.recoveryCenter.runRecovery(for: hash, action: overrideAction)
                return json([
                    "infoHash": record.infoHash,
                    "name": record.name,
                    "reason": record.reason.rawValue,
                    "action": record.action.rawValue,
                    "source": record.source.rawValue,
                    "success": record.success,
                    "message": record.message,
                    "timestamp": record.timestamp.timeIntervalSince1970,
                ] as [String: Any])
            } catch let error as RecoveryCenter.Error {
                return Response(
                    status: .notFound,
                    body: .init(byteBuffer: ByteBuffer(string: error.localizedDescription))
                )
            } catch {
                return Response(
                    status: .badRequest,
                    body: .init(byteBuffer: ByteBuffer(string: error.localizedDescription))
                )
            }
        }

        // MARK: Controllarr: post-processor

        router.get("/api/controllarr/postprocessor") { _, _ -> Response in
            let records = await services.postProcessor.snapshot()
            let out: [[String: Any]] = records.map(postProcessorRecord)
            return json(out)
        }
        router.post("/api/controllarr/postprocessor/retry") { request, _ -> Response in
            let form = FormParser.parse(try await request.body.collect(upTo: 64 * 1024))
            guard let hash = form["hash"], !hash.isEmpty else {
                return Response(status: .badRequest)
            }
            do {
                let record = try await services.postProcessor.retry(infoHash: hash)
                return json(postProcessorRecord(record))
            } catch let error as PostProcessor.Error {
                let status: HTTPResponse.Status = switch error {
                case .recordNotFound, .torrentNotFound:
                    .notFound
                case .recordNotRetryable:
                    .badRequest
                }
                return Response(
                    status: status,
                    body: .init(byteBuffer: ByteBuffer(string: error.localizedDescription))
                )
            } catch {
                return Response(
                    status: .badRequest,
                    body: .init(byteBuffer: ByteBuffer(string: error.localizedDescription))
                )
            }
        }

        // MARK: Controllarr: seeding enforcement log

        router.get("/api/controllarr/seeding") { _, _ -> Response in
            let records = await services.seedingPolicy.snapshot()
            let out: [[String: Any]] = records.map { e in
                [
                    "infoHash": e.infoHash,
                    "name": e.name,
                    "reason": e.reason,
                    "action": e.action.rawValue,
                    "timestamp": e.timestamp.timeIntervalSince1970,
                ]
            }
            return json(out)
        }

        // MARK: Controllarr: disk space

        router.get("/api/controllarr/diskspace") { _, _ -> Response in
            let status = await services.diskSpaceMonitor.snapshot()
            return json(diskSpaceStatus(status))
        }
        router.post("/api/controllarr/diskspace/recheck") { _, _ -> Response in
            await services.diskSpaceMonitor.forceEvaluate()
            let status = await services.diskSpaceMonitor.snapshot()
            return json(diskSpaceStatus(status))
        }

        // MARK: Controllarr: network diagnostics

        router.get("/api/controllarr/network") { _, _ -> Response in
            let settings = await services.store.settings()
            let vpn = await services.vpnMonitor.snapshot()
            let snapshot = NetworkDiagnostics.snapshot(
                bindHost: settings.webUIHost,
                bindPort: settings.webUIPort,
                vpnStatus: vpn
            )
            return json(networkDiagnosticsDict(snapshot))
        }

        // MARK: Controllarr: VPN monitor

        router.get("/api/controllarr/vpn") { _, _ -> Response in
            let status = await services.vpnMonitor.snapshot()
            return json([
                "isConnected": status.isConnected,
                "interfaceName": status.interfaceName ?? "" as Any,
                "interfaceIP": status.interfaceIP ?? "" as Any,
                "killSwitchEngaged": status.killSwitchEngaged,
                "pausedCount": status.pausedHashes.count,
                "boundToVPN": status.boundToVPN,
            ] as [String: Any])
        }

        // MARK: Controllarr: *arr notifier

        router.get("/api/controllarr/arr") { _, _ -> Response in
            let entries = await services.arrNotifier.snapshot()
            let out: [[String: Any]] = entries.map { n in
                [
                    "infoHash": n.infoHash,
                    "name": n.name,
                    "endpoint": n.endpoint,
                    "success": n.success,
                    "message": n.message,
                    "timestamp": n.timestamp.timeIntervalSince1970,
                ]
            }
            return json(out)
        }

        // MARK: Controllarr: log viewer

        router.get("/api/controllarr/log") { request, _ -> Response in
            let query = FormParser.parseQuery(request.uri.query ?? "")
            let limit = Int(query["limit"] ?? "") ?? 500
            let entries = await services.logger.snapshot(limit: limit)
            let out: [[String: Any]] = entries.map { e in
                [
                    "id": e.id.uuidString,
                    "timestamp": e.timestamp.timeIntervalSince1970,
                    "level": e.level.rawValue,
                    "source": e.source,
                    "message": e.message,
                ]
            }
            return json(out)
        }

        return sessions
    }

    // MARK: - Cookie helper

    /// Extract the SID value from the `Cookie` request header.
    static func extractSID(from request: Request) -> String? {
        guard let cookie = request.headers[.cookie] else { return nil }
        for part in cookie.split(separator: ";") {
            let trimmed = part.trimmingCharacters(in: .whitespaces)
            if trimmed.hasPrefix("SID=") {
                return String(trimmed.dropFirst(4))
            }
        }
        return nil
    }

    // MARK: - Serialization helpers

    static func categoryDict(_ c: Persistence.Category) -> [String: Any] {
        var dict: [String: Any] = [
            "name": c.name,
            "savePath": c.savePath,
            "extractArchives": c.extractArchives,
            "blockedExtensions": c.blockedExtensions,
        ]
        if let v = c.completePath { dict["completePath"] = v }
        if let v = c.maxRatio { dict["maxRatio"] = v }
        if let v = c.maxSeedingTimeMinutes { dict["maxSeedingTimeMinutes"] = v }
        return dict
    }

    static func settingsDict(_ s: Settings) -> [String: Any] {
        var dict: [String: Any] = [
            "listenPortRangeStart": Int(s.listenPortRangeStart),
            "listenPortRangeEnd":   Int(s.listenPortRangeEnd),
            "stallThresholdMinutes": s.stallThresholdMinutes,
            "defaultSavePath": s.defaultSavePath,
            "webUIHost": s.webUIHost,
            "webUIPort": s.webUIPort,
            "webUIUsername": s.webUIUsername,
            "seedLimitAction": s.seedLimitAction.rawValue,
            "minimumSeedTimeMinutes": s.minimumSeedTimeMinutes,
            "healthStallMinutes": s.healthStallMinutes,
            "healthReannounceOnStall": s.healthReannounceOnStall,
            "recoveryRules": s.recoveryRules.map { rule in
                [
                    "enabled": rule.enabled,
                    "trigger": rule.trigger.rawValue,
                    "action": rule.action.rawValue,
                    "delayMinutes": rule.delayMinutes,
                ] as [String: Any]
            },
            "vpnEnabled": s.vpnEnabled,
            "vpnKillSwitch": s.vpnKillSwitch,
            "vpnBindInterface": s.vpnBindInterface,
            "vpnInterfacePrefix": s.vpnInterfacePrefix,
            "vpnMonitorIntervalSeconds": s.vpnMonitorIntervalSeconds,
            "diskSpaceMonitorPath": s.diskSpaceMonitorPath,
            "arrReSearchAfterHours": s.arrReSearchAfterHours,
            "bandwidthSchedule": s.bandwidthSchedule.map { rule -> [String: Any] in
                var d: [String: Any] = [
                    "name": rule.name,
                    "enabled": rule.enabled,
                    "daysOfWeek": rule.daysOfWeek,
                    "startHour": rule.startHour,
                    "startMinute": rule.startMinute,
                    "endHour": rule.endHour,
                    "endMinute": rule.endMinute,
                ]
                if let v = rule.maxDownloadKBps { d["maxDownloadKBps"] = v }
                if let v = rule.maxUploadKBps { d["maxUploadKBps"] = v }
                return d
            },
            "arrEndpoints": s.arrEndpoints.map { ep -> [String: Any] in
                [
                    "name": ep.name,
                    "kind": ep.kind.rawValue,
                    "baseURL": ep.baseURL,
                ]
            },
        ]
        if let v = s.globalMaxRatio { dict["globalMaxRatio"] = v }
        if let v = s.globalMaxSeedingTimeMinutes { dict["globalMaxSeedingTimeMinutes"] = v }
        if let v = s.diskSpaceMinimumGB { dict["diskSpaceMinimumGB"] = v }
        return dict
    }

    static func stageString(_ stage: PostProcessor.Stage) -> String {
        switch stage {
        case .pending:                    return "pending"
        case .movingStorage(let target, _): return "moving:\(target)"
        case .extracting:                 return "extracting"
        case .done:                       return "done"
        case .failed(let reason):         return "failed:\(reason)"
        }
    }

    static func postProcessorRecord(_ record: PostProcessor.Record) -> [String: Any] {
        var dict: [String: Any] = [
            "infoHash": record.infoHash,
            "name": record.name,
            "stage": stageString(record.stage),
            "canRetry": PostProcessor.isRetryable(stage: record.stage),
            "lastUpdated": record.lastUpdated.timeIntervalSince1970,
        ]
        if let c = record.category { dict["category"] = c }
        if let m = record.message { dict["message"] = m }
        return dict
    }

    static func diskSpaceStatus(_ status: DiskSpaceMonitor.Status) -> [String: Any] {
        [
            "freeBytes": status.freeBytes,
            "thresholdBytes": status.thresholdBytes,
            "monitorPath": status.monitorPath,
            "shortfallBytes": status.shortfallBytes,
            "isPaused": status.isPaused,
            "pausedCount": status.pausedHashes.count,
            "pausedHashes": status.pausedHashes.sorted(),
        ]
    }

    static func networkDiagnosticsDict(_ snapshot: NetworkDiagnostics.Snapshot) -> [String: Any] {
        var dict: [String: Any] = [
            "bindHost": snapshot.bindHost,
            "bindPort": snapshot.bindPort,
            "localOpenURL": snapshot.localOpenURL,
            "remoteAccessConfigured": snapshot.remoteAccessConfigured,
            "suggestedRemoteURLs": snapshot.suggestedRemoteURLs,
            "vpnConnected": snapshot.vpnConnected,
            "vpnInterfaceName": snapshot.vpnInterfaceName ?? "",
            "vpnInterfaceIP": snapshot.vpnInterfaceIP ?? "",
            "vpnBoundToTorrentEngine": snapshot.vpnBoundToTorrentEngine,
            "lanInterfaces": snapshot.lanInterfaces.map { iface in
                [
                    "name": iface.name,
                    "ip": iface.ip,
                ]
            },
        ]
        if let recommended = snapshot.recommendedRemoteURL {
            dict["recommendedRemoteURL"] = recommended
        }
        if let warning = snapshot.warning {
            dict["warning"] = warning
        }
        return dict
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
        return jsonData(data)
    }

    static func jsonData(_ data: Data, contentDisposition: String? = nil) -> Response {
        var headers = HTTPFields()
        headers[.contentType] = "application/json"
        if let contentDisposition {
            headers[.contentDisposition] = contentDisposition
        }
        return Response(status: .ok, headers: headers, body: .init(byteBuffer: ByteBuffer(bytes: data)))
    }
}

// MARK: - Session store

public actor SessionStore {
    private static let maxTokens = 50
    private static let tokenLifetime: TimeInterval = 3600 // 1 hour

    private var tokens: [String: Date] = [:]  // sid -> creation date

    func issue() -> String {
        // If at capacity, prune expired first
        if tokens.count >= Self.maxTokens {
            pruneExpired()
        }
        // If still at capacity, drop the oldest
        if tokens.count >= Self.maxTokens,
           let oldest = tokens.min(by: { $0.value < $1.value })?.key {
            tokens.removeValue(forKey: oldest)
        }
        let sid = UUID().uuidString.replacingOccurrences(of: "-", with: "")
        tokens[sid] = Date()
        return sid
    }

    func valid(_ sid: String) -> Bool {
        guard let created = tokens[sid] else { return false }
        if Date().timeIntervalSince(created) > Self.tokenLifetime {
            tokens.removeValue(forKey: sid)
            return false
        }
        return true
    }

    func revoke(_ sid: String) {
        tokens.removeValue(forKey: sid)
    }

    private func pruneExpired() {
        let now = Date()
        tokens = tokens.filter { now.timeIntervalSince($0.value) <= Self.tokenLifetime }
    }
}
