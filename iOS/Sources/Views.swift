import SwiftUI
import UniformTypeIdentifiers

private let ink = Color(red: 0.07, green: 0.16, blue: 0.21)
private let sea = Color(red: 0.08, green: 0.62, blue: 0.52)

struct RemoteRoot: View {
    @Environment(RemoteModel.self) private var model
    @State private var showInstances = false
    var body: some View {
        TabView {
            NavigationStack { OverviewView() }.tabItem { Label("Overview", systemImage: "square.grid.2x2") }
            NavigationStack { TorrentsView() }.tabItem { Label("Torrents", systemImage: "arrow.down.circle") }
            NavigationStack { CategoriesView() }.tabItem { Label("Categories", systemImage: "folder") }
            NavigationStack { ServerSettingsView() }.tabItem { Label("Settings", systemImage: "slider.horizontal.3") }
        }
        .overlay(alignment: .top) {
            if let error = model.error {
                HStack {
                    Image(systemName: "exclamationmark.triangle.fill")
                    Text(error).font(.caption).lineLimit(3)
                    Button { model.error = nil } label: { Image(systemName: "xmark") }
                }.padding(12).background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16))
                    .padding().shadow(color: .black.opacity(0.08), radius: 10)
            }
        }
        .sheet(isPresented: $showInstances) { NavigationStack { InstancesView() } }
        .task { if model.instances.isEmpty { showInstances = true } }
    }
}

private struct OverviewView: View {
    @Environment(RemoteModel.self) private var model
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                VStack(alignment: .leading, spacing: 14) {
                    HStack {
                        Label(model.connected ? "CONNECTED" : "OFFLINE", systemImage: "circle.fill").font(.caption2.bold()).tracking(2)
                        Spacer()
                        Text(model.platform).font(.caption)
                    }.foregroundStyle(.white.opacity(0.75))
                    Text(model.selected?.name ?? "Your library,\nwherever you are.")
                        .font(.system(size: 35, weight: .semibold, design: .serif)).foregroundStyle(.white)
                    HStack(alignment: .firstTextBaseline) {
                        Text("\(model.total)").font(.system(size: 58, weight: .light, design: .rounded)).monospacedDigit()
                        Text("torrents").font(.headline).foregroundStyle(.white.opacity(0.65))
                    }.foregroundStyle(.white)
                    HStack(spacing: 24) {
                        metric("DOWNLOAD", value: rate(model.session.object[model.key("downloadRate", "download_rate")]))
                        metric("UPLOAD", value: rate(model.session.object[model.key("uploadRate", "upload_rate")]))
                        metric("PORT", value: model.session.object[model.key("listenPort", "listen_port")]?.text ?? "--")
                    }
                }.padding(26).frame(maxWidth: .infinity, alignment: .leading)
                    .background(LinearGradient(colors: [ink, Color(red: 0.12, green: 0.35, blue: 0.38)], startPoint: .topLeading, endPoint: .bottomTrailing), in: RoundedRectangle(cornerRadius: 28))

                HStack {
                    Text("Command Center").font(.title2.bold())
                    Spacer()
                    NavigationLink { InstancesView() } label: { Image(systemName: "server.rack").font(.title3) }.accessibilityLabel("Manage instances")
                }
                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
                    NavigationLink { ActivityView() } label: { quick("Activity", "bell.badge", "Recent server events") }
                    NavigationLink { AlertsView() } label: { quick("Alerts", "bell", "Choose what matters") }
                    NavigationLink { DiagnosticsView(title: "VPN & Network", route: "vpn") } label: { quick("VPN & Network", "network", "Binding and protection") }
                    NavigationLink { DiagnosticsView(title: "Health", route: "health") } label: { quick("Health", "heart.text.clipboard", "Issues and recovery") }
                }.buttonStyle(.plain)
                VStack(spacing: 0) {
                    NavigationLink { DiagnosticsView(title: "Post-Processing", route: "postprocessor") } label: { navRow("Post-Processing", icon: "shippingbox") }
                    Divider()
                    NavigationLink { DiagnosticsView(title: "Seeding Policy", route: "seeding") } label: { navRow("Seeding Policy", icon: "arrow.up.forward.circle") }
                    Divider()
                    NavigationLink { DiagnosticsView(title: "Recovery", route: "recovery") } label: { navRow("Recovery", icon: "wrench.and.screwdriver") }
                    Divider()
                    NavigationLink { DiagnosticsView(title: "Server Log", route: "log?limit=200") } label: { navRow("Server Log", icon: "text.alignleft") }
                }.background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 18))
            }.padding(20)
        }.background(Color(.systemGroupedBackground)).navigationTitle("Controllarr")
            .toolbar { ToolbarItem(placement: .topBarTrailing) { NavigationLink { InstancesView() } label: { Image(systemName: "server.rack") } } }
            .refreshable { await model.refresh() }
    }
    private func metric(_ title: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title).font(.system(size: 9, weight: .bold)).tracking(1.5).foregroundStyle(.white.opacity(0.6))
            Text(value).font(.subheadline.bold()).monospacedDigit().foregroundStyle(.white)
        }
    }
    private func quick(_ title: String, _ icon: String, _ subtitle: String) -> some View {
        VStack(alignment: .leading, spacing: 9) {
            Image(systemName: icon).font(.title2).foregroundStyle(sea)
            Text(title).font(.headline).foregroundStyle(.primary)
            Text(subtitle).font(.caption).foregroundStyle(.secondary).lineLimit(2)
        }.frame(maxWidth: .infinity, minHeight: 110, alignment: .leading).padding(16)
            .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 20))
    }
    private func navRow(_ title: String, icon: String) -> some View {
        HStack { Label(title, systemImage: icon); Spacer(); Image(systemName: "chevron.right").font(.caption) }.padding(16)
    }
}

private struct InstancesView: View {
    @Environment(RemoteModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @State private var discovery = Discovery()
    @State private var editing: Instance?
    var body: some View {
        List {
            Section("Saved Servers") {
                ForEach(model.instances) { instance in
                    HStack {
                        Button { Task { await model.select(instance); dismiss() } } label: {
                            VStack(alignment: .leading) { Text(instance.name).font(.headline); Text(instance.address).font(.caption).foregroundStyle(.secondary) }
                        }
                        Spacer()
                        if instance.id == model.selectedID { Image(systemName: "checkmark.circle.fill").foregroundStyle(sea) }
                        Button { editing = instance } label: { Image(systemName: "pencil") }.buttonStyle(.borderless)
                    }.swipeActions { Button("Forget", role: .destructive) { Task { await model.delete(instance) } } }
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
        }.navigationTitle("Instances").toolbar { Button("Close") { dismiss() } }
            .task { discovery.start() }.onDisappear { discovery.stop() }
            .sheet(item: $editing) { instance in NavigationStack { InstanceEditor(instance: instance) } }
    }
}

private struct InstanceEditor: View {
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
                    .keyboardType(.URL).textInputAutocapitalization(.never).autocorrectionDisabled()
                TextField("WebUI Username", text: $instance.username).textInputAutocapitalization(.never).autocorrectionDisabled()
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

private struct TorrentsView: View {
    @Environment(RemoteModel.self) private var model
    @State private var selection: Set<String> = []
    @State private var selecting = false
    @State private var confirmDelete = false
    @State private var showAdd = false
    var body: some View {
        @Bindable var model = model
        List {
            Section {
                Picker("Category", selection: $model.category) {
                    Text("All Categories").tag(String?.none)
                    ForEach(model.categoryNames, id: \.self) { Text($0).tag(Optional($0)) }
                }
                if selecting {
                    Button(selection.count == model.torrents.count ? "Deselect Page" : "Select Page (up to 100)") {
                        selection = selection.count == model.torrents.count ? [] : Set(model.torrents.map(\.hash))
                    }
                }
            }
            ForEach(model.torrents) { torrent in
                if selecting {
                    Button { if !selection.insert(torrent.hash).inserted { selection.remove(torrent.hash) } } label: {
                        HStack { Image(systemName: selection.contains(torrent.hash) ? "checkmark.circle.fill" : "circle"); TorrentRow(torrent: torrent) }
                    }.buttonStyle(.plain)
                } else {
                    NavigationLink { TorrentDetail(torrent: torrent) } label: { TorrentRow(torrent: torrent) }
                        .contextMenu {
                            Button("Pause") { Task { await model.action("pause", hashes: [torrent.hash]) } }
                            Button("Resume") { Task { await model.action("resume", hashes: [torrent.hash]) } }
                            Button("Remove...", role: .destructive) { selection = [torrent.hash]; confirmDelete = true }
                        }
                }
            }
            Section {
                HStack {
                    Button("Previous") { model.offset = max(0, model.offset - 100); selection = []; Task { await model.refresh() } }.disabled(model.offset == 0)
                    Spacer()
                    Text("\(model.total == 0 ? 0 : model.offset + 1)-\(min(model.offset + 100, model.total)) of \(model.total)").font(.caption).monospacedDigit()
                    Spacer()
                    Button("Next") { model.offset += 100; selection = []; Task { await model.refresh() } }.disabled(model.offset + 100 >= model.total)
                }
            }
        }.navigationTitle("Torrents").searchable(text: $model.search, prompt: "Name or hash")
            .task(id: model.search) { try? await Task.sleep(for: .milliseconds(300)); if !Task.isCancelled { selection = []; await model.changeFilter() } }
            .onChange(of: model.category) { _, _ in selection = []; Task { await model.changeFilter() } }
            .refreshable { await model.refresh() }
            .toolbar {
                ToolbarItem(placement: .topBarLeading) { Button(selecting ? "Done" : "Select") { selecting.toggle(); selection = [] } }
                ToolbarItem(placement: .topBarTrailing) { Button("Add", systemImage: "plus") { showAdd = true }.disabled(model.client == nil) }
                ToolbarItemGroup(placement: .bottomBar) {
                    if !selection.isEmpty {
                        Button("Pause", systemImage: "pause") { Task { await model.action("pause", hashes: selection) } }
                        Button("Resume", systemImage: "play") { Task { await model.action("resume", hashes: selection) } }
                        Menu("Category", systemImage: "folder") {
                            Button("Uncategorized") { Task { await model.action("setCategory", hashes: selection, extra: ["category": ""]) } }
                            ForEach(model.categoryNames, id: \.self) { category in Button(category) { Task { await model.action("setCategory", hashes: selection, extra: ["category": category]) } } }
                        }
                        Spacer()
                        Button("Remove \(selection.count)", systemImage: "trash", role: .destructive) { confirmDelete = true }
                    }
                }
            }.disabled(model.busy)
            .confirmationDialog("Remove \(selection.count) torrent(s)?", isPresented: $confirmDelete, titleVisibility: .visible) {
                Button("Remove from Controllarr (Keep Files)") { remove(false) }
                Button("Remove and Delete Files from Server", role: .destructive) { remove(true) }
                Button("Cancel", role: .cancel) { }
            } message: { Text("Disk deletion happens on the selected server and cannot be undone.") }
            .sheet(isPresented: $showAdd) { NavigationStack { AddTorrentView() } }
    }
    private func remove(_ files: Bool) { let hashes = selection; selection = []; Task { await model.action("delete", hashes: hashes, extra: ["deleteFiles": String(files)]) } }
}

private struct TorrentRow: View {
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

private struct AddTorrentView: View {
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
                TextEditor(text: $magnets).frame(minHeight: 150).textInputAutocapitalization(.never).autocorrectionDisabled()
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

private struct CategoriesView: View {
    @Environment(RemoteModel.self) private var model
    @State private var editing: CategoryDraft?
    @State private var deleting: String?
    private struct CategoryDraft: Identifiable { let id = UUID(); let value: JSONValue }
    var body: some View {
        List {
            ForEach(Array(model.categories.enumerated()), id: \.offset) { _, category in
                Button { editing = CategoryDraft(value: category) } label: {
                    VStack(alignment: .leading, spacing: 5) { Text(category.object["name"]?.text ?? "Category").font(.headline); Text(category.object[model.key("savePath", "save_path")]?.text ?? "").font(.caption).foregroundStyle(.secondary) }
                }.swipeActions { Button("Delete", role: .destructive) { deleting = category.object["name"]?.text } }
            }
        }.navigationTitle("Categories").refreshable { await model.refresh() }
            .toolbar { Button("New Category", systemImage: "plus") {
                editing = CategoryDraft(value: .object(["name": .string(""), model.key("savePath", "save_path"): .string(""),
                    model.key("completePath", "complete_path"): .string(""), model.key("extractArchives", "extract_archives"): .bool(false),
                    model.key("blockedExtensions", "blocked_extensions"): .array([]), model.key("createTorrentSubfolder", "create_torrent_subfolder"): .bool(true),
                    model.key("maxRatio", "max_ratio"): .null, model.key("maxSeedingTimeMinutes", "max_seeding_time_minutes"): .null]))
            }.disabled(model.client == nil) }
            .sheet(item: $editing) { draft in NavigationStack { DocumentEditor(title: "Category", original: draft.value) { try await model.saveCategory($0) } } }
            .confirmationDialog("Delete category? Torrents and files will remain.", isPresented: Binding(get: { deleting != nil }, set: { if !$0 { deleting = nil } }), titleVisibility: .visible) {
                Button("Delete Category", role: .destructive) { if let name = deleting { Task { do { try await model.removeCategory(name) } catch { model.error = error.localizedDescription } } }; deleting = nil }
            }
    }
}

private struct ServerSettingsView: View {
    @Environment(RemoteModel.self) private var model
    @State private var settings: JSONValue?
    var body: some View {
        List {
            Section("Remote App") {
                NavigationLink { InstancesView() } label: { Label("Instances", systemImage: "server.rack") }
                NavigationLink { AlertsView() } label: { Label("Notifications", systemImage: "bell") }
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
                if let original = settings { NavigationStack { DocumentEditor(title: "Server Settings", original: original) { try await model.saveSettings(original: original, edited: $0) } } }
            }
    }
}

private struct DocumentEditor: View {
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

private struct JSONFields: View {
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
private struct JSONField: View {
    let title: String
    @Binding var value: JSONValue
    var body: some View {
        switch value {
        case .object, .array:
            NavigationLink { Form { JSONFields(value: $value) }.navigationTitle(title) } label: { LabeledContent(title, value: value.text) }
        case .bool(let bool):
            Toggle(title, isOn: Binding(get: { if case .bool(let b) = value { return b }; return bool }, set: { value = .bool($0) }))
        case .number(let number):
            LabeledContent(title) { TextField(title, value: Binding(get: { if case .number(let n) = value { return n }; return number }, set: { value = .number($0) }), format: .number.grouping(.never)).multilineTextAlignment(.trailing).keyboardType(.numbersAndPunctuation) }
        case .string:
            if title.lowercased().contains("password") || title.lowercased().contains("api key") {
                SecureField(title, text: stringBinding).textInputAutocapitalization(.never).autocorrectionDisabled()
            } else {
                LabeledContent(title) { TextField(title, text: stringBinding, axis: .vertical).multilineTextAlignment(.trailing).textInputAutocapitalization(.never).autocorrectionDisabled() }
            }
        case .null:
            LabeledContent(title) { TextField("Inherited / unset", text: Binding(get: { value == .null ? "" : value.text }, set: {
                if $0.isEmpty { value = .null } else if let n = Double($0) { value = .number(n) } else { value = .string($0) }
            })).multilineTextAlignment(.trailing) }
        }
    }
    private var stringBinding: Binding<String> { Binding(get: { value.text }, set: { value = .string($0) }) }
}

private struct AlertsView: View {
    @Environment(RemoteModel.self) private var model
    private let kinds = [("completed", "Torrent Completed"), ("error", "Torrent Error"), ("vpn_disconnected", "VPN Disconnected"), ("port_changed", "Listen Port Changed")]
    var body: some View {
        Form {
            Section("Notify Me") {
                ForEach(kinds, id: \.0) { kind, title in Toggle(title, isOn: Binding(get: { model.notificationKinds.contains(kind) }, set: { enabled in Task { await model.setNotifications(kind, enabled: enabled) } })) }
            }
            Section("Delivery") {
                Text("Alerts are checked while Controllarr is open and during iOS background refresh opportunities. Background delivery is not guaranteed, and force-quitting the app can prevent refresh. This release does not use an APNs push relay.").font(.footnote).foregroundStyle(.secondary)
                Text("The first connection establishes a baseline, so existing completed torrents do not generate a flood of alerts. Events are retained by the server in memory (512 maximum); a server restart starts a new baseline.").font(.footnote).foregroundStyle(.secondary)
            }
        }.navigationTitle("Notifications")
    }
}

private struct ActivityView: View {
    @Environment(RemoteModel.self) private var model
    var body: some View {
        List {
            if model.events.isEmpty { ContentUnavailableView("No New Events", systemImage: "bell", description: Text("New completions, errors, VPN disconnects, and port changes appear here after connecting.")) }
            ForEach(model.events) { event in VStack(alignment: .leading, spacing: 5) { Text(event.title).font(.headline); Text(event.message).font(.subheadline); Text(Date(timeIntervalSince1970: event.timestamp), style: .relative).font(.caption).foregroundStyle(.secondary) } }
        }.navigationTitle("Activity").refreshable { await model.refresh() }
    }
}

private struct DiagnosticsView: View {
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

private struct ReadJSON: View {
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

private struct TorrentDetail: View {
    @Environment(RemoteModel.self) private var model
    let torrent: RemoteTorrent
    @State private var files: JSONValue = .array([])
    @State private var confirm = false
    @State private var confirmRepair = false
    @State private var showMove = false
    @State private var movePath = ""
    var body: some View {
        List {
            Section {
                TorrentRow(torrent: model.torrents.first { $0.hash == torrent.hash } ?? torrent)
                LabeledContent("Content Path", value: torrent.content_path).font(.caption).textSelection(.enabled)
                LabeledContent("Save Path", value: torrent.save_path).font(.caption).textSelection(.enabled)
                Text(torrent.hash).font(.caption2.monospaced()).textSelection(.enabled)
            }
            Section("Controls") {
                Button("Resume", systemImage: "play") { Task { await model.action("resume", hashes: [torrent.hash]) } }
                Button("Pause", systemImage: "pause") { Task { await model.action("pause", hashes: [torrent.hash]) } }
                Button("Force Resume", systemImage: "forward") { Task { await model.action("setForceStart", hashes: [torrent.hash], extra: ["value": "true"]) } }
                Button("Reannounce", systemImage: "antenna.radiowaves.left.and.right") { Task { await model.action("reannounce", hashes: [torrent.hash]) } }
                Button("Force Recheck", systemImage: "checkmark.shield") { Task { await model.action("recheck", hashes: [torrent.hash]) } }
                Button("Move Storage...", systemImage: "folder.badge.arrow.down") { movePath = torrent.save_path; showMove = true }
                Button("Repair Import Folder Layout...", systemImage: "folder.badge.gearshape") { confirmRepair = true }
                Menu("Category") {
                    Button("Uncategorized") { Task { await model.action("setCategory", hashes: [torrent.hash], extra: ["category": ""]) } }
                    ForEach(model.categoryNames, id: \.self) { name in Button(name) { Task { await model.action("setCategory", hashes: [torrent.hash], extra: ["category": name]) } } }
                }
                Button("Remove...", role: .destructive) { confirm = true }
            }
            Section("Files") {
                ForEach(Array(files.array.enumerated()), id: \.offset) { index, file in
                    Picker(file.object["name"]?.text ?? "File \(index)", selection: Binding(get: { files.array[index].object["priority"] ?? .number(1) }, set: { new in
                        var list = files.array; var row = list[index].object; row["priority"] = new; list[index] = .object(row); files = .array(list)
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
        }.navigationTitle("Torrent").task { do { files = try await model.client?.json("api/v2/torrents/files", query: ["hash": torrent.hash]) ?? .array([]) } catch { model.error = error.localizedDescription } }
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
                TextField("Absolute path on server", text: $movePath).textInputAutocapitalization(.never).autocorrectionDisabled()
                Button("Move") { Task { await model.action("setLocation", hashes: [torrent.hash], extra: ["location": movePath]) } }
                Button("Cancel", role: .cancel) { }
            } message: { Text("Enter the destination on the server, not on your phone. Files may take time to move.") }
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
private func rate(_ value: JSONValue?) -> String {
    guard case .number(let number) = value else { return "--" }
    return ByteCountFormatter.string(fromByteCount: Int64(number), countStyle: .binary) + "/s"
}
