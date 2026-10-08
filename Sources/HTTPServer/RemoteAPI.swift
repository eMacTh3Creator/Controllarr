import Foundation
import Hummingbird
import TorrentEngine

/// Small, bounded event journal. First observation is a baseline, not a flood
/// of completion notifications for an existing library.
actor RemoteEvents {
    struct Event: Codable, Sendable {
        let id: Int
        let kind: String
        let title: String
        let message: String
        let hash: String?
        let timestamp: Double
    }
    struct Page: Codable, Sendable {
        let epoch: String
        let cursor: Int
        let reset: Bool
        let events: [Event]
    }
    private let epoch = UUID().uuidString
    private var cursor = 0
    private var events: [Event] = []
    private var previous: [String: (Bool, String)] = [:]
    private var port: UInt16?
    private var vpnConnected: Bool?

    func observe(_ torrents: [TorrentStats], port: UInt16, vpnEnabled: Bool, connected: Bool) {
        var next: [String: (Bool, String)] = [:]
        next.reserveCapacity(torrents.count)
        for t in torrents {
            let complete = t.hasMetadata && t.progress >= 1
            if let old = previous[t.infoHash] {
                if complete && !old.0 { append("completed", t.name, "Torrent completed", t.infoHash) }
                if !t.errorMessage.isEmpty && old.1 != t.errorMessage { append("error", t.name, t.errorMessage, t.infoHash) }
            }
            next[t.infoHash] = (complete, t.errorMessage)
        }
        previous = next
        if let old = self.port, old != port { append("port_changed", "Listen port changed", "\(old) -> \(port)", nil) }
        if vpnEnabled, vpnConnected == true, !connected { append("vpn_disconnected", "VPN disconnected", "Check the protected torrent adapter", nil) }
        self.port = port
        vpnConnected = vpnEnabled ? connected : nil
    }

    private func append(_ kind: String, _ title: String, _ message: String, _ hash: String?) {
        cursor += 1
        events.append(Event(id: cursor, kind: kind, title: title, message: message, hash: hash, timestamp: Date().timeIntervalSince1970))
        if events.count > 512 { events.removeFirst(events.count - 512) }
    }

    func page(epoch requestedEpoch: String?, cursor requestedCursor: Int?) -> Page {
        let reset = requestedEpoch != epoch || requestedCursor == nil || requestedCursor! > cursor || requestedCursor! < (events.first?.id ?? 1) - 1
        return Page(epoch: epoch, cursor: cursor, reset: reset,
                    events: reset ? [] : events.filter { $0.id > requestedCursor! })
    }
}

enum RemoteAPI {
    static func install(on router: Router<BasicRequestContext>, services: HTTPServer.Services, events: RemoteEvents) {
        router.post("/api/v2/torrents/setLocation") { request, _ -> Response in
            let form = FormParser.parse(try await request.body.collect(upTo: 256 * 1024))
            guard let path = form["location"], path.hasPrefix("/") else { return Response(status: .badRequest) }
            for hash in (form["hashes"] ?? "").split(separator: "|") {
                guard await services.engine.move(infoHash: String(hash), to: URL(fileURLWithPath: path)) else { return Response(status: .conflict) }
            }
            return QBittorrentAPI.plainText("Ok.")
        }
        router.post("/api/v2/torrents/reannounce") { request, _ -> Response in
            let form = FormParser.parse(try await request.body.collect(upTo: 256 * 1024))
            for hash in (form["hashes"] ?? "").split(separator: "|") { _ = await services.engine.reannounce(infoHash: String(hash)) }
            return QBittorrentAPI.plainText("Ok.")
        }
        router.post("/api/v2/torrents/recheck") { request, _ -> Response in
            let form = FormParser.parse(try await request.body.collect(upTo: 256 * 1024))
            for hash in (form["hashes"] ?? "").split(separator: "|") { _ = await services.engine.forceRecheck(infoHash: String(hash)) }
            return QBittorrentAPI.plainText("Ok.")
        }
        router.post("/api/controllarr/torrents/:hash/repairLayout") { request, context -> Response in
            let form = FormParser.parse(try await request.body.collect(upTo: 1024))
            guard form["confirmed"] == "true", let hash = context.parameters.get("hash") else { return Response(status: .badRequest) }
            return await services.engine.repairContentLayout(infoHash: hash) ? QBittorrentAPI.plainText("Ok.") : Response(status: .conflict)
        }
        router.get("/api/controllarr/remote") { _, _ -> Response in
            QBittorrentAPI.json(["protocol": 1, "platform": "macOS", "version": "2.3.0",
                "settingsStyle": "camelCase", "features": ["paged_torrents", "events", "categories", "files", "trackers", "peers", "repair_layout", "move_storage"],
                "notifications": "polling", "bonjourService": "_controllarr._tcp"] as [String: Any])
        }
        router.get("/api/controllarr/remote/torrents") { request, _ -> Response in
            let query = FormParser.parseQuery(request.uri.query ?? "")
            let search = query["search"] ?? ""
            let category = query["category"]
            let offset = max(0, Int(query["offset"] ?? "0") ?? 0)
            let limit = min(500, max(1, Int(query["limit"] ?? "100") ?? 100))
            let all = await services.engine.pollStats().filter { t in
                (category == nil || t.category == category) && (search.isEmpty || t.name.localizedCaseInsensitiveContains(search) || t.infoHash.localizedCaseInsensitiveContains(search))
            }.sorted { $0.infoHash < $1.infoHash }
            let items = all.dropFirst(min(offset, all.count)).prefix(limit).map { QBTorrentInfo.from($0, categoryOverlay: [:]).asDictionary }
            return QBittorrentAPI.json(["total": all.count, "offset": offset, "items": items] as [String: Any])
        }
        router.get("/api/controllarr/remote/events") { request, _ -> Response in
            let query = FormParser.parseQuery(request.uri.query ?? "")
            let page = await events.page(epoch: query["epoch"], cursor: query["cursor"].flatMap(Int.init))
            return QBittorrentAPI.jsonData(try JSONEncoder().encode(page))
        }
    }
}

@MainActor
final class RemoteDiscovery {
    private var service: NetService?
    func start(host: String, port: Int) {
        guard !["127.0.0.1", "localhost", "::1"].contains(host), (1...65535).contains(port) else { return }
        let service = NetService(domain: "local.", type: "_controllarr._tcp.", name: "Controllarr on \(ProcessInfo.processInfo.hostName)", port: Int32(port))
        service.setTXTRecord(NetService.data(fromTXTRecord: ["protocol": Data("1".utf8), "platform": Data("macOS".utf8)]))
        service.publish()
        self.service = service
    }
    func stop() { service?.stop(); service = nil }
}
