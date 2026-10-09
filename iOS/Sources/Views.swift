import SwiftUI
import UniformTypeIdentifiers

let ink = Color(red: 0.07, green: 0.16, blue: 0.21)
let sea = Color(red: 0.08, green: 0.62, blue: 0.52)

struct InstancesView: View {
    @Environment(RemoteModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @State private var discovery = Discovery()
    @State private var editing: Instance?
    var isSheet = false
    var body: some View {
        List {
            Section("Saved Servers") {
                ForEach(model.instances) { instance in
                    HStack {
                        Button { Task { await model.select(instance); if isSheet { dismiss() } } } label: {
                            VStack(alignment: .leading) { Text(instance.name).font(.headline); Text(instance.address).font(.caption).foregroundStyle(.secondary) }
                        }
                        Spacer()
                        if instance.id == model.selectedID { Image(systemName: "checkmark.circle.fill").foregroundStyle(sea) }
                        Button { editing = instance } label: { Image(systemName: "pencil") }.buttonStyle(.borderless)
                    }.swipeActions { Button("Forget", role: .destructive) { Task { await model.delete(instance) } } }
                        .contextMenu { Button("Edit") { editing = instance }; Button("Forget", role: .destructive) { Task { await model.delete(instance) } } }
                }
                Button("Add by Hostname or Address", systemImage: "plus") { editing = Instance(name: "My Server", address: "") }
            }
            Section {
                ForEach(discovery.instances) { instance in
                    Button { editing = instance } label: { Label(instance.name, systemImage: "network") }
                }
                Text(discovery.message).font(.caption).foregroundStyle(.secondary)
                Text("For discovery, the server must listen on a LAN address, with discovery enabled and private-network firewall access allowed. Hostnames also work across a private VPN or HTTPS reverse proxy.").font(.caption).foregroundStyle(.secondary)
            } header: { Text("Nearby") }
        }.navigationTitle("Instances").toolbar { if isSheet { Button("Close") { dismiss() } } }
            .task { discovery.start() }.onDisappear { discovery.stop() }
            .sheet(item: $editing) { instance in NavigationStack { InstanceEditor(instance: instance) }.remoteSheet() }
    }
}

struct InstanceEditor: View {
    @Environment(RemoteModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @State var instance: Instance
    @State private var password = ""
    @State private var saving = false
    @State private var error: String?
    var body: some View {
        Form {
            Section("Server") {
                TextField("Name", text: $instance.name)
                TextField("https://plex.example.com or plexbox.local:8791", text: $instance.address)
                    .remoteURLInput()
                TextField("WebUI Username", text: $instance.username).remotePlainInput()
                SecureField("WebUI Password", text: $password)
            }
            Section {
                Toggle("Allow Unencrypted HTTP", isOn: $instance.allowInsecureHTTP)
                Text("HTTP sends credentials and commands without encryption. Enable only on a trusted LAN or encrypted private VPN. For Internet access, use HTTPS with a trusted certificate; do not expose port 8791 directly.").font(.caption).foregroundStyle(.secondary)
            }
            if let error { Text(error).foregroundStyle(.red) }
            Button(saving ? "Connecting..." : "Save & Connect") {
                saving = true
                Task {
                    do { try await model.save(instance, password: password); dismiss() }
                    catch { self.error = error.localizedDescription }
                    saving = false
                }
            }.disabled(saving || password.isEmpty || instance.address.isEmpty || instance.name.isEmpty)
        }.navigationTitle("Connect Server").toolbar { Button("Cancel") { dismiss() } }
            .task { password = CredentialStore.load(instance.id) ?? "" }
    }
}

struct TorrentRow: View {
    let torrent: RemoteTorrent
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(torrent.name.isEmpty ? torrent.hash : torrent.name).font(.subheadline.weight(.semibold)).lineLimit(2)
            ProgressView(value: torrent.progress).tint(torrent.state == "error" ? .red : sea)
            HStack {
                Text(torrent.state).foregroundStyle(torrent.state == "error" ? .red : .secondary)
                Text(torrent.progress, format: .percent.precision(.fractionLength(0)))
                Spacer()
                Text(ByteCountFormatter.string(fromByteCount: torrent.dlspeed, countStyle: .binary) + "/s").monospacedDigit()
            }.font(.caption)
            if !torrent.category.isEmpty { Text(torrent.category).font(.caption2.bold()).foregroundStyle(sea) }
        }.padding(.vertical, 5)
    }
}

struct AddTorrentView: View {
    @Environment(RemoteModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @State private var magnets = ""
    @State private var category = ""
    @State private var importer = false
    @State private var busy = false
    @State private var error: String?
    var body: some View {
        Form {
            Section("Destination") {
                Picker("Category", selection: $category) { Text("Uncategorized").tag(""); ForEach(model.categoryNames, id: \.self) { Text($0).tag($0) } }
                Text("Files are downloaded on the server, in a separate torrent subfolder.").font(.caption).foregroundStyle(.secondary)
            }
            Section("Magnet Links") {
                TextEditor(text: $magnets).frame(minHeight: 150).remotePlainInput()
                Button("Add Magnet Links") { perform { try await model.addMagnet(magnets, category: category) } }.disabled(magnets.isEmpty)
            }
            Button("Choose .torrent File", systemImage: "doc.badge.plus") { importer = true }
            if let error { Text(error).foregroundStyle(.red) }
        }.disabled(busy).navigationTitle("Add Torrent").toolbar { Button("Cancel") { dismiss() } }
            .fileImporter(isPresented: $importer, allowedContentTypes: [UTType(filenameExtension: "torrent") ?? .data]) { result in
                switch result { case .success(let url): perform { try await model.addTorrent(url, category: category) }; case .failure(let e): error = e.localizedDescription }
            }
    }
    private func perform(_ work: @escaping @MainActor () async throws -> Void) {
        busy = true
        Task { do { try await work(); dismiss() } catch { self.error = error.localizedDescription }; busy = false }
    }
}

struct CategoriesView: View {
    @Environment(RemoteModel.self) private var model
    @State private var editing: CategoryDraft?
    @State private var deleting: String?
    struct CategoryDraft: Identifiable { let id = UUID(); let value: JSONValue }
    var body: some View {
        List {
            ForEach(Array(model.categories.enumerated()), id: \.offset) { _, category in
                Button { editing = CategoryDraft(value: category) } label: {
                    VStack(alignment: .leading, spacing: 5) { Text(category.object["name"]?.text ?? "Category").font(.headline); Text(category.object[model.key("savePath", "save_path")]?.text ?? "").font(.caption).foregroundStyle(.secondary) }
                }.swipeActions { Button("Delete", role: .destructive) { deleting = category.object["name"]?.text } }
                    .contextMenu { Button("Edit") { editing = CategoryDraft(value: category) }; Button("Delete", role: .destructive) { deleting = category.object["name"]?.text } }
            }
        }.navigationTitle("Categories").refreshable { await model.refresh() }
            .toolbar { Button("New Category", systemImage: "plus") {
                editing = CategoryDraft(value: .object(["name": .string(""), model.key("savePath", "save_path"): .string(""),
                    model.key("completePath", "complete_path"): .string(""), model.key("extractArchives", "extract_archives"): .bool(false),
                    model.key("blockedExtensions", "blocked_extensions"): .array([]), model.key("createTorrentSubfolder", "create_torrent_subfolder"): .bool(true),
                    model.key("maxRatio", "max_ratio"): .null, model.key("maxSeedingTimeMinutes", "max_seeding_time_minutes"): .null]))
            }.disabled(model.client == nil) }
            .sheet(item: $editing) { draft in NavigationStack { DocumentEditor(title: "Category", original: draft.value) { try await model.saveCategory($0) } }.remoteSheet() }
            .confirmationDialog("Delete category? Torrents and files will remain.", isPresented: Binding(get: { deleting != nil }, set: { if !$0 { deleting = nil } }), titleVisibility: .visible) {
                Button("Delete Category", role: .destructive) { if let name = deleting { Task { do { try await model.removeCategory(name) } catch { model.error = error.localizedDescription } } }; deleting = nil }
            }
    }
}

struct ServerSettingsView: View {
    @Environment(RemoteModel.self) private var model
    @Environment(RemoteWorkspace.self) private var workspace
    @State private var settings: JSONValue?
    var body: some View {
        List {
            Section("Remote App") {
                Button("Instances", systemImage: "server.rack") { workspace.destination = .instances }
                Button("Notifications", systemImage: "bell") { workspace.destination = .alerts }
            }
            Section("Selected Server") {
                Button("Edit Server Settings", systemImage: "slider.horizontal.3") { Task {
                    do { settings = try await model.client?.json("api/controllarr/settings") } catch { model.error = error.localizedDescription }
                } }.disabled(model.client == nil)
                Button("Cycle Listen Port", systemImage: "arrow.triangle.2.circlepath") { Task {
                    do { try await model.client?.action("api/controllarr/port/cycle", values: [:]); await model.refresh() } catch { model.error = error.localizedDescription }
                } }.disabled(model.client == nil)
                Text("Settings are read from the server's own schema. Host/port and discovery changes may require a server restart. Changing VPN protection or download paths can interrupt transfers.").font(.caption).foregroundStyle(.secondary)
            }
        }.navigationTitle("Settings")
            .sheet(isPresented: Binding(get: { settings != nil }, set: { if !$0 { settings = nil } })) {
                if let original = settings { NavigationStack { DocumentEditor(title: "Server Settings", original: original) { try await model.saveSettings(original: original, edited: $0) } }.remoteSheet() }
            }
    }
}

struct DocumentEditor: View {
    @Environment(\.dismiss) private var dismiss
    let title: String
    let original: JSONValue
    let save: (JSONValue) async throws -> Void
    @State private var value: JSONValue = .null
    @State private var saving = false
    @State private var error: String?
    var body: some View {
        Form { JSONFields(value: $value, lockName: title == "Category" && !(original.object["name"]?.text.isEmpty ?? true)); if let error { Text(error).foregroundStyle(.red) } }
            .navigationTitle(title).disabled(saving)
            .task { value = original }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) { Button(saving ? "Saving..." : "Save") {
                    saving = true
                    Task { do { try await save(value); dismiss() } catch { self.error = error.localizedDescription }; saving = false }
                } }
            }
    }
}

struct JSONFields: View {
    @Binding var value: JSONValue
    var lockName = false
    var body: some View {
        switch value {
        case .object(let object):
            ForEach(object.keys.sorted(), id: \.self) { key in
                JSONField(title: humanize(key), value: Binding(get: { value.object[key] ?? .null }, set: { new in var o = value.object; o[key] = new; value = .object(o) }))
                    .disabled(key == "name" && lockName)
            }
        case .array(let array):
            ForEach(array.indices, id: \.self) { index in
                JSONField(title: "Item \(index + 1)", value: Binding(get: { value.array.indices.contains(index) ? value.array[index] : .null }, set: { new in var a = value.array; if a.indices.contains(index) { a[index] = new; value = .array(a) } }))
                    .swipeActions { Button("Delete", role: .destructive) { var a = value.array; if a.indices.contains(index) { a.remove(at: index); value = .array(a) } } }
            }
            Button("Add Item") { value = .array(value.array + [value.array.last ?? .string("")]) }
        default: JSONField(title: "Value", value: $value)
        }
    }
}
struct JSONField: View {
    let title: String
    @Binding var value: JSONValue
    var body: some View {
        switch value {
        case .object, .array:
            NavigationLink { Form { JSONFields(value: $value) }.navigationTitle(title) } label: { LabeledContent(title, value: value.text) }
        case .bool(let bool):
            Toggle(title, isOn: Binding(get: { if case .bool(let b) = value { return b }; return bool }, set: { value = .bool($0) }))
        case .number(let number):
            LabeledContent(title) { TextField(title, value: Binding(get: { if case .number(let n) = value { return n }; return number }, set: { value = .number($0) }), format: .number.grouping(.never)).multilineTextAlignment(.trailing).remoteNumericInput() }
        case .string:
            if title.lowercased().contains("password") || title.lowercased().contains("api key") {
                SecureField(title, text: stringBinding).remotePlainInput()
            } else {
                LabeledContent(title) { TextField(title, text: stringBinding, axis: .vertical).multilineTextAlignment(.trailing).remotePlainInput() }
            }
        case .null:
            LabeledContent(title) { TextField("Inherited / unset", text: Binding(get: { value == .null ? "" : value.text }, set: {
                if $0.isEmpty { value = .null } else if let n = Double($0) { value = .number(n) } else { value = .string($0) }
            })).multilineTextAlignment(.trailing) }
        }
    }
    private var stringBinding: Binding<String> { Binding(get: { value.text }, set: { value = .string($0) }) }
}

struct AlertsView: View {
    @Environment(RemoteModel.self) private var model
    private let kinds = [("completed", "Torrent Completed"), ("error", "Torrent Error"), ("vpn_disconnected", "VPN Disconnected"), ("port_changed", "Listen Port Changed")]
    var body: some View {
        Form {
            Section("Notify Me") {
                ForEach(kinds, id: \.0) { kind, title in Toggle(title, isOn: Binding(get: { model.notificationKinds.contains(kind) }, set: { enabled in Task { await model.setNotifications(kind, enabled: enabled) } })) }
            }
            Section("Delivery") {
                #if os(macOS)
                Text("Alerts are checked while Controllarr Remote is running, including when its window is in the background. Quitting the app stops delivery. This release does not use an APNs push relay.").font(.footnote).foregroundStyle(.secondary)
                #else
                Text("Alerts are checked while Controllarr is open and during iOS background refresh opportunities. Background delivery is not guaranteed, and force-quitting the app can prevent refresh. This release does not use an APNs push relay.").font(.footnote).foregroundStyle(.secondary)
                #endif
                Text("The first connection establishes a baseline, so existing completed torrents do not generate a flood of alerts. Events are retained by the server in memory (512 maximum); a server restart starts a new baseline.").font(.footnote).foregroundStyle(.secondary)
            }
        }.navigationTitle("Notifications")
    }
}

struct ActivityView: View {
    @Environment(RemoteModel.self) private var model
    var body: some View {
        List {
            if model.events.isEmpty { ContentUnavailableView("No New Events", systemImage: "bell", description: Text("New completions, errors, VPN disconnects, and port changes appear here after connecting.")) }
            ForEach(model.events) { event in VStack(alignment: .leading, spacing: 5) { Text(event.title).font(.headline); Text(event.message).font(.subheadline); Text(Date(timeIntervalSince1970: event.timestamp), style: .relative).font(.caption).foregroundStyle(.secondary) } }
        }.navigationTitle("Activity").refreshable { await model.refresh() }
    }
}

struct DiagnosticsView: View {
    @Environment(RemoteModel.self) private var model
    let title: String
    let route: String
    @State private var value: JSONValue = .null
    @State private var error: String?
    var body: some View {
        List {
            if let error { Text(error).foregroundStyle(.red) }
            if ["health", "postprocessor"].contains(route), case .array(let records) = value {
                ForEach(Array(records.enumerated()), id: \.offset) { _, record in
                    Section(record.object["name"]?.text ?? "Torrent") {
                        ReadJSON(value: record)
                        if let hash = (record.object["infoHash"] ?? record.object["info_hash"])?.text {
                            Button(route == "health" ? "Clear Health Issue" : "Retry Post-Processing") {
                                Task {
                                    do {
                                        try await model.client?.action("api/controllarr/" + (route == "health" ? "health/clear" : "postprocessor/retry"), values: ["hash": hash])
                                        await load()
                                    } catch { self.error = error.localizedDescription }
                                }
                            }
                        }
                    }
                }
            } else { ReadJSON(value: value) }
        }.navigationTitle(title).task { await load() }.refreshable { await load() }
    }
    private func load() async {
        guard let client = model.client else { return }
        do {
            let parts = route.split(separator: "?", maxSplits: 1)
            value = try await client.json("api/controllarr/" + parts[0], query: parts.count > 1 ? ["limit": "200"] : [:])
            error = nil
        } catch { self.error = error.localizedDescription }
    }
}

struct ReadJSON: View {
    let value: JSONValue
    var body: some View {
        switch value {
        case .array(let array):
            if array.isEmpty { Text("No records").foregroundStyle(.secondary) }
            ForEach(Array(array.enumerated()), id: \.offset) { index, item in Section("\(index + 1)") { ReadJSON(value: item) } }
        case .object(let object):
            ForEach(object.keys.sorted(), id: \.self) { key in
                switch object[key]! {
                case .array, .object: NavigationLink(humanize(key)) { List { ReadJSON(value: object[key]!) }.navigationTitle(humanize(key)) }
                default: LabeledContent(humanize(key)) { Text(object[key]!.text).textSelection(.enabled).font(.caption).multilineTextAlignment(.trailing) }
                }
            }
        default: Text(value.text)
        }
    }
}

struct TorrentDetail: View {
    @Environment(RemoteModel.self) private var model
    let torrent: RemoteTorrent
    private var current: RemoteTorrent { model.torrents.first { $0.hash == torrent.hash } ?? torrent }
    @State private var files: JSONValue = .array([])
    @State private var confirm = false
    @State private var confirmRepair = false
    @State private var showMove = false
    @State private var movePath = ""
    var body: some View {
        List {
            Section {
                TorrentRow(torrent: current)
                LabeledContent("Content Path", value: current.content_path).font(.caption).textSelection(.enabled)
                LabeledContent("Save Path", value: current.save_path).font(.caption).textSelection(.enabled)
                Text(torrent.hash).font(.caption2.monospaced()).textSelection(.enabled)
            }
            Section("Controls") {
                Button("Resume", systemImage: "play") { Task { await model.action("resume", hashes: [torrent.hash]) } }
                Button("Pause", systemImage: "pause") { Task { await model.action("pause", hashes: [torrent.hash]) } }
                Button("Force Resume", systemImage: "forward") { Task { await model.action("setForceStart", hashes: [torrent.hash], extra: ["value": "true"]) } }
                Button("Reannounce", systemImage: "antenna.radiowaves.left.and.right") { Task { await model.action("reannounce", hashes: [torrent.hash]) } }
                Button("Force Recheck", systemImage: "checkmark.shield") { Task { await model.action("recheck", hashes: [torrent.hash]) } }
                Button("Move Storage...", systemImage: "folder.badge.arrow.down") { movePath = current.save_path; showMove = true }
                Button("Repair Import Folder Layout...", systemImage: "folder.badge.gearshape") { confirmRepair = true }
                Menu("Category") {
                    Button("Uncategorized") { Task { await model.action("setCategory", hashes: [torrent.hash], extra: ["category": ""]) } }
                    ForEach(model.categoryNames, id: \.self) { name in Button(name) { Task { await model.action("setCategory", hashes: [torrent.hash], extra: ["category": name]) } } }
                }
                Button("Remove...", role: .destructive) { confirm = true }
            }
            Section("Files") {
                ForEach(Array(files.array.enumerated()), id: \.offset) { index, file in
                    Picker(file.object["name"]?.text ?? "File \(index)", selection: Binding(get: { files.array.indices.contains(index) ? (files.array[index].object["priority"] ?? .number(1)) : .number(1) }, set: { new in
                        var list = files.array; guard list.indices.contains(index) else { return }; var row = list[index].object; row["priority"] = new; list[index] = .object(row); files = .array(list)
                    })) {
                        Text("Skip").tag(JSONValue.number(0))
                        Text("Low").tag(JSONValue.number(1))
                        Text("Normal").tag(JSONValue.number(model.isWindows ? 3 : 4))
                        if model.isWindows { Text("High").tag(JSONValue.number(4)) }
                        Text("Higher").tag(JSONValue.number(6))
                        Text("Maximum").tag(JSONValue.number(7))
                    }
                }
                Button("Apply File Priorities") { Task { await saveFiles() } }.disabled(files.array.isEmpty)
            }
            NavigationLink { DiagnosticsView(title: "Trackers", route: "torrents/\(torrent.hash)/trackers") } label: { Label("Trackers", systemImage: "antenna.radiowaves.left.and.right") }
            NavigationLink { DiagnosticsView(title: "Peers", route: "torrents/\(torrent.hash)/peers") } label: { Label("Peers", systemImage: "person.2") }
        }.navigationTitle("Torrent").task(id: "\(model.selectedID?.uuidString ?? "")-\(torrent.hash)") {
                files = .array([])
                let serverID = model.selectedID
                do {
                    let result = try await model.client?.json("api/v2/torrents/files", query: ["hash": torrent.hash]) ?? .array([])
                    if !Task.isCancelled && model.selectedID == serverID { files = result }
                } catch { if !Task.isCancelled { model.error = error.localizedDescription } }
            }
            .confirmationDialog("Remove Torrent?", isPresented: $confirm, titleVisibility: .visible) {
                Button("Remove (Keep Files)") { Task { await model.action("delete", hashes: [torrent.hash], extra: ["deleteFiles": "false"]) } }
                Button("Delete Files from Server", role: .destructive) { Task { await model.action("delete", hashes: [torrent.hash], extra: ["deleteFiles": "true"]) } }
            }
            .confirmationDialog("Repair Import Folder Layout?", isPresented: $confirmRepair, titleVisibility: .visible) {
                Button("Move Flat Content into a Torrent Subfolder") { Task {
                    do { try await model.client?.action("api/controllarr/torrents/\(torrent.hash)/repairLayout", values: ["confirmed": "true"]); await model.refresh() }
                    catch { model.error = error.localizedDescription }
                } }
            } message: { Text("This changes storage on the server. Proper folders are left alone. Conflicting destinations are rejected; check the server log if a move fails.") }
            .alert("Move Torrent Storage", isPresented: $showMove) {
                TextField("Absolute path on server", text: $movePath).remotePlainInput()
                Button("Move") { Task { await model.action("setLocation", hashes: [torrent.hash], extra: ["location": movePath]) } }
                Button("Cancel", role: .cancel) { }
            } message: { Text("Enter the destination on the server, not on this device. Files may take time to move.") }
    }
    private func saveFiles() async {
        let priorities = files.array.map { $0.object["priority"] ?? .number(1) }
        let payload: JSONValue = model.isWindows ? .object(Dictionary(uniqueKeysWithValues: priorities.enumerated().map { (String($0.offset), $0.element) })) : .object(["priorities": .array(priorities)])
        do { try await model.client?.post("api/controllarr/torrents/\(torrent.hash)/files", value: payload) } catch { model.error = error.localizedDescription }
    }
}

private func humanize(_ key: String) -> String {
    key.replacingOccurrences(of: "([a-z])([A-Z])", with: "$1 $2", options: .regularExpression).replacingOccurrences(of: "_", with: " ").capitalized
}
func rate(_ value: JSONValue?) -> String {
    guard case .number(let number) = value else { return "--" }
    return ByteCountFormatter.string(fromByteCount: Int64(number), countStyle: .binary) + "/s"
}
