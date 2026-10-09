import Foundation
import Observation
import UserNotifications
#if os(iOS)
import BackgroundTasks
#endif

@MainActor @Observable
final class RemoteModel {
    var instances: [Instance] = []
    var selectedID: UUID?
    var client: RemoteClient?
    var platform = ""
    var torrents: [RemoteTorrent] = []
    var total = 0
    var offset = 0
    var search = ""
    private(set) var appliedSearch = ""
    var category: String?
    var categories: [JSONValue] = []
    var session: JSONValue = .object([:])
    var events: [RemoteEvent] = []
    var error: String?
    var connected = false
    var busy = false
    var lastUpdated: Date?
    var notificationKinds: Set<String> = Set(UserDefaults.standard.stringArray(forKey: "notificationKinds") ?? [])
    private(set) var refreshing = false
    private var generation = UUID()
    private var pollTask: Task<Void, Never>?
    private var active = false
    private var refreshPending = false
    #if DEBUG
    private let layoutPreview = ProcessInfo.processInfo.arguments.contains("--layout-preview")
    #endif

    init() {
        #if DEBUG
        if layoutPreview { loadLayoutPreview(); return }
        #endif
        if let data = UserDefaults.standard.data(forKey: "instances"), let saved = try? JSONDecoder().decode([Instance].self, from: data) { instances = saved }
        selectedID = UserDefaults.standard.string(forKey: "selectedID").flatMap(UUID.init(uuidString:)) ?? instances.first?.id
    }
    var selected: Instance? { instances.first { $0.id == selectedID } }
    var isWindows: Bool { platform == "Windows" }
    var categoryNames: [String] { categories.compactMap { $0.object["name"]?.text }.sorted() }
    func key(_ camel: String, _ snake: String) -> String { isWindows ? snake : camel }
    func persist() {
        UserDefaults.standard.set(try? JSONEncoder().encode(instances), forKey: "instances")
        UserDefaults.standard.set(selectedID?.uuidString, forKey: "selectedID")
    }
    func save(_ instance: Instance, password: String) async throws {
        guard instances.count < 8 || instances.contains(where: { $0.id == instance.id }) else { throw RemoteError.http(0, "Maximum eight saved instances") }
        _ = try ServerAddress.normalize(instance.address, allowHTTP: instance.allowInsecureHTTP)
        try CredentialStore.save(password, for: instance.id)
        instances.removeAll { $0.id == instance.id }
        instances.append(instance)
        selectedID = instance.id
        persist()
        await connect()
    }
    func delete(_ instance: Instance) async {
        CredentialStore.delete(instance.id)
        instances.removeAll { $0.id == instance.id }
        if selectedID == instance.id { selectedID = instances.first?.id; await connect() }
        persist()
    }
    func select(_ instance: Instance) async {
        selectedID = instance.id
        persist()
        await connect()
    }
    func connect() async {
        generation = UUID()
        let token = generation
        pollTask?.cancel()
        await client?.close()
        client = nil
        connected = false
        torrents = []; categories = []; events = []; session = .object([:]); offset = 0; total = 0; lastUpdated = nil
        guard let instance = selected else { return }
        guard let password = CredentialStore.load(instance.id) else { error = "Enter this server's password again in Instances."; return }
        do {
            let client = try RemoteClient(instance: instance, password: password)
            let capabilities = try await client.json("api/controllarr/remote")
            guard token == generation else { await client.close(); return }
            guard capabilities.object["protocol"] == .number(1) else { await client.close(); throw RemoteError.unsupportedServer }
            self.client = client
            platform = capabilities.object["platform"]?.text ?? ""
            connected = true
            error = nil
            await refresh()
            startPolling()
        } catch { if token == generation { self.error = error.localizedDescription } }
    }
    func setActive(_ value: Bool) {
        #if DEBUG
        if layoutPreview { return }
        #endif
        #if os(macOS)
        guard !active else { return }
        active = true
        if client == nil { Task { await connect() } } else { startPolling() }
        #else
        active = value
        if value {
            if client == nil { Task { await connect() } } else { startPolling() }
        } else { pollTask?.cancel(); pollTask = nil; scheduleBackground() }
        #endif
    }
    private func startPolling() {
        pollTask?.cancel()
        guard active else { return }
        pollTask = Task { [weak self] in
            while !Task.isCancelled {
                await self?.refresh()
                do { try await Task.sleep(for: .seconds(4)) } catch { break }
            }
        }
    }
    func refresh() async {
        guard let client else { return }
        guard !refreshing else { refreshPending = true; return }
        refreshing = true
        let token = generation
        let request = RemotePageRequest(offset: offset, search: search, category: category)
        defer {
            refreshing = false
            if refreshPending {
                refreshPending = false
                Task { await refresh() }
            }
        }
        do {
            let page = try JSONDecoder().decode(TorrentPage.self, from: await client.request("api/controllarr/remote/torrents", query: request.query))
            let cats = try await client.json("api/controllarr/categories")
            let stats = try await client.json("api/controllarr/stats")
            guard token == generation else { return }
            guard request == RemotePageRequest(offset: offset, search: search, category: category) else {
                refreshPending = true
                return
            }
            if torrents != page.items { torrents = page.items }
            if total != page.total { total = page.total }
            if categories != cats.array { categories = cats.array }
            if session != stats { session = stats }
            if offset >= total && offset > 0 { offset = RemotePageRequest.lastOffset(total: total); refreshPending = true }
            try await pollEvents(client)
            guard token == generation else { return }
            connected = true; error = nil; lastUpdated = Date()
        } catch is CancellationError { }
        catch { if token == generation { connected = false; self.error = error.localizedDescription } }
    }
    func changeFilter() async { appliedSearch = search; offset = 0; await refresh() }
    func action(_ name: String, hashes: Set<String>, extra: [String: String] = [:]) async {
        guard let client, !hashes.isEmpty, !busy else { return }
        busy = true
        defer { busy = false }
        do {
            let values = extra.merging(["hashes": hashes.sorted().joined(separator: "|")]) { _, new in new }
            try await client.action("api/v2/torrents/" + name, values: values)
            await refresh()
        } catch { self.error = error.localizedDescription }
    }
    func addMagnet(_ text: String, category: String) async throws {
        guard let client else { throw RemoteError.authentication }
        let links = text.split(whereSeparator: \.isNewline).map(String.init)
        guard !links.isEmpty, links.allSatisfy({ $0.hasPrefix("magnet:?") }) else { throw RemoteError.http(0, "Enter valid magnet links, one per line") }
        try await client.action("api/v2/torrents/add", values: ["urls": links.joined(separator: "\n"), "category": category, "contentLayout": "Subfolder"])
        await refresh()
    }
    func addTorrent(_ url: URL, category: String) async throws {
        guard let client else { throw RemoteError.authentication }
        let access = url.startAccessingSecurityScopedResource()
        defer { if access { url.stopAccessingSecurityScopedResource() } }
        let data = try Data(contentsOf: url, options: .mappedIfSafe)
        guard data.count <= 9 * 1024 * 1024 else { throw RemoteError.http(0, "Torrent file must be smaller than 9 MiB") }
        let boundary = UUID().uuidString
        var body = Data("--\(boundary)\r\nContent-Disposition: form-data; name=\"category\"\r\n\r\n\(category)\r\n--\(boundary)\r\nContent-Disposition: form-data; name=\"contentLayout\"\r\n\r\nSubfolder\r\n--\(boundary)\r\nContent-Disposition: form-data; name=\"torrents\"; filename=\"upload.torrent\"\r\nContent-Type: application/x-bittorrent\r\n\r\n".utf8)
        body.append(data); body.append(Data("\r\n--\(boundary)--\r\n".utf8))
        _ = try await client.request("api/v2/torrents/add", method: "POST", body: body, contentType: "multipart/form-data; boundary=\(boundary)")
        await refresh()
    }
    func saveSettings(original: JSONValue, edited: JSONValue) async throws {
        guard let client else { throw RemoteError.authentication }
        let latest = try await client.json("api/controllarr/settings")
        try await client.post("api/controllarr/settings", value: JSONValue.mergingChanges(original: original, edited: edited, latest: latest))
        await refresh()
    }
    func saveCategory(_ value: JSONValue) async throws {
        guard let client else { throw RemoteError.authentication }
        try await client.post("api/controllarr/categories", value: value)
        await refresh()
    }
    func removeCategory(_ name: String) async throws {
        guard let client else { throw RemoteError.authentication }
        let encoded = name.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed.subtracting(CharacterSet(charactersIn: "/?#%")))!
        _ = try await client.request("api/controllarr/categories/" + encoded, method: "DELETE")
        await refresh()
    }
    func setNotifications(_ kind: String, enabled: Bool) async {
        if enabled {
            do {
                guard try await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge]) else { error = "Enable notifications for Controllarr Remote in system Settings."; return }
                notificationKinds.insert(kind)
            } catch { self.error = error.localizedDescription }
        } else { notificationKinds.remove(kind) }
        UserDefaults.standard.set(Array(notificationKinds), forKey: "notificationKinds")
        scheduleBackground()
    }
    private func pollEvents(_ client: RemoteClient) async throws {
        let token = generation
        let instance = client.instance
        let defaults = UserDefaults.standard
        let prefix = "events." + instance.id.uuidString
        var query: [String: String] = [:]
        if let epoch = defaults.string(forKey: prefix + ".epoch") {
            query = ["epoch": epoch, "cursor": String(defaults.integer(forKey: prefix + ".cursor"))]
        }
        let page = try JSONDecoder().decode(EventPage.self, from: await client.request("api/controllarr/remote/events", query: query))
        guard token == generation, instance.id == selectedID, !Task.isCancelled else { return }
        if !page.reset {
            events = Array((Array(page.events.reversed()) + events).prefix(100))
            for event in page.events.suffix(20) where notificationKinds.contains(event.kind) && Date().timeIntervalSince1970 - event.timestamp < 3600 {
                let content = UNMutableNotificationContent()
                content.title = event.title
                content.body = instance.name + ": " + event.message
                content.sound = .default
                try? await UNUserNotificationCenter.current().add(UNNotificationRequest(identifier: prefix + ".\(page.epoch).\(event.id)", content: content, trigger: nil))
            }
        }
        defaults.set(page.epoch, forKey: prefix + ".epoch")
        defaults.set(page.cursor, forKey: prefix + ".cursor")
    }
    func scheduleBackground() {
        #if os(iOS)
        guard !notificationKinds.isEmpty else { BGTaskScheduler.shared.cancel(taskRequestWithIdentifier: "com.controllarr.remote.refresh"); return }
        let request = BGAppRefreshTaskRequest(identifier: "com.controllarr.remote.refresh")
        request.earliestBeginDate = Date().addingTimeInterval(15 * 60)
        try? BGTaskScheduler.shared.submit(request)
        #endif
    }
    func backgroundRefresh() async {
        guard !notificationKinds.isEmpty else { return }
        // Keep one background opportunity bounded; foreground supports all saved servers.
        for instance in instances.filter({ $0.id == selectedID }).prefix(1) {
            guard !Task.isCancelled, let password = CredentialStore.load(instance.id), let client = try? RemoteClient(instance: instance, password: password) else { continue }
            try? await pollEvents(client)
            await client.close()
        }
        scheduleBackground()
    }
}
