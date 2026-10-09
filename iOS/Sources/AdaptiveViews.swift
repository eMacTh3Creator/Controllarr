import SwiftUI

struct RemoteRoot: View {
    @Environment(RemoteModel.self) private var model
    @Environment(RemoteWorkspace.self) private var workspace
    @State private var columns: NavigationSplitViewVisibility = .all

    var body: some View {
        @Bindable var workspace = workspace
        GeometryReader { geometry in
            Group {
                if useSidebar(geometry.size) {
                    NavigationSplitView(columnVisibility: $columns) {
                        sidebar.navigationSplitViewColumnWidth(min: 190, ideal: 225, max: 280)
                    } detail: {
                        NavigationStack { destination(workspace.destination).toolbar { serverToolbar } }
                    }
                    .navigationSplitViewStyle(.balanced)
                } else {
                    TabView(selection: Binding(get: { workspace.destination.tab }, set: { workspace.destination = $0 })) {
                        ForEach([RemoteDestination.overview, .torrents, .categories, .settings]) { tab in
                            NavigationStack {
                                destination(workspace.destination.tab == tab ? workspace.destination : tab)
                                    .toolbar {
                                        if workspace.destination.tab == tab && workspace.destination != tab {
                                            ToolbarItem(placement: .navigation) {
                                                Button { workspace.destination = tab } label: { Label(tab.title, systemImage: "chevron.left") }
                                            }
                                        }
                                        serverToolbar
                                    }
                            }.tabItem { Label(tab.title, systemImage: tab.icon) }.tag(tab)
                        }
                    }
                }
            }
        }
        .tint(sea)
        .safeAreaInset(edge: .top, spacing: 0) {
            if let error = model.error {
                HStack(alignment: .top) {
                    Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.orange)
                    Text(error).font(.caption).textSelection(.enabled)
                    Spacer(minLength: 8)
                    Button { model.error = nil } label: { Image(systemName: "xmark") }.accessibilityLabel("Dismiss error")
                }.padding(12).background(.regularMaterial)
            }
        }
        .sheet(isPresented: $workspace.showInstances) { NavigationStack { InstancesView(isSheet: true) }.remoteSheet() }
        .sheet(isPresented: $workspace.showAdd) { NavigationStack { AddTorrentView() }.remoteSheet() }
        .task { if model.instances.isEmpty { workspace.showInstances = true } }
        .onChange(of: model.selectedID) { _, _ in workspace.selectedHashes = []; workspace.showInspector = false }
    }

    private func useSidebar(_ size: CGSize) -> Bool {
        #if os(macOS)
        true
        #else
        RemoteLayout.usesSidebar(width: size.width, height: size.height)
        #endif
    }

    private var sidebar: some View {
        List(selection: Binding<RemoteDestination?>(get: { workspace.destination }, set: { if let value = $0 { workspace.destination = value } })) {
            Section("Library") { sidebarRows([.overview, .torrents, .categories]) }
            Section("Operations") { sidebarRows([.activity, .vpn, .health, .postprocessor, .seeding, .recovery, .log]) }
            Section("Remote") { sidebarRows([.settings, .alerts, .instances]) }
        }
        .navigationTitle("Controllarr")
        .safeAreaInset(edge: .bottom) {
            VStack(alignment: .leading, spacing: 6) {
                Label(model.connected ? "Connected" : "Offline", systemImage: "circle.fill")
                    .font(.caption.bold()).foregroundStyle(model.connected ? sea : .secondary)
                Text(model.selected?.name ?? "Choose an instance").font(.subheadline).lineLimit(1)
                if let updated = model.lastUpdated { Text(updated, style: .time).font(.caption2).foregroundStyle(.secondary) }
            }.frame(maxWidth: .infinity, alignment: .leading).padding(16).background(.bar)
        }
    }

    private func sidebarRows(_ destinations: [RemoteDestination]) -> some View {
        ForEach(destinations) { item in Label(item.title, systemImage: item.icon).tag(item) }
    }

    @ToolbarContentBuilder private var serverToolbar: some ToolbarContent {
        ToolbarItemGroup(placement: .automatic) {
            Button { Task { await model.refresh() } } label: { Image(systemName: "arrow.clockwise") }
                .help("Refresh server").accessibilityLabel("Refresh server").disabled(model.client == nil || model.refreshing)
            Menu {
                ForEach(model.instances) { instance in
                    Button { Task { await model.select(instance) } } label: {
                        Label(instance.name, systemImage: instance.id == model.selectedID ? "checkmark.circle.fill" : "server.rack")
                    }
                }
                Divider()
                Button("Manage Instances...") { workspace.showInstances = true }
            } label: { Image(systemName: "server.rack") }.help("Switch server").accessibilityLabel("Switch server")
        }
    }

    @ViewBuilder private func destination(_ item: RemoteDestination) -> some View {
        switch item {
        case .overview: OverviewView()
        case .torrents: TorrentsView()
        case .categories: CategoriesView()
        case .settings: ServerSettingsView()
        case .instances: InstancesView()
        case .alerts: AlertsView()
        case .activity: ActivityView()
        case .vpn: DiagnosticsView(title: item.title, route: "vpn")
        case .health: DiagnosticsView(title: item.title, route: "health")
        case .postprocessor: DiagnosticsView(title: item.title, route: "postprocessor")
        case .seeding: DiagnosticsView(title: item.title, route: "seeding")
        case .recovery: DiagnosticsView(title: item.title, route: "recovery")
        case .log: DiagnosticsView(title: item.title, route: "log?limit=200")
        }
    }
}

struct OverviewView: View {
    @Environment(RemoteModel.self) private var model
    @Environment(RemoteWorkspace.self) private var workspace
    @Environment(\.dynamicTypeSize) private var textSize
    var body: some View {
        GeometryReader { geometry in
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    if geometry.size.width >= 1000 && !textSize.isAccessibilitySize {
                        HStack(alignment: .top, spacing: 20) { hero; recentActivity.frame(width: 310) }
                    } else { hero }
                    ViewThatFits(in: .horizontal) {
                        HStack { actions }
                        VStack(alignment: .leading, spacing: 12) { actions }
                    }.buttonStyle(.bordered)
                    Text("Command Center").font(.title2.bold())
                    LazyVGrid(columns: Array(repeating: GridItem(.flexible(), alignment: .topLeading), count: RemoteLayout.dashboardColumns(width: geometry.size.width, accessibilityText: textSize.isAccessibilitySize)), spacing: 14) {
                        quick(.torrents, "Search, inspect, and manage transfers")
                        quick(.categories, "Organize paths and torrent rules")
                        quick(.vpn, "Adapter binding and protection")
                        quick(.health, "Find issues and recover transfers")
                        quick(.postprocessor, "Moves and archive extraction")
                        quick(.seeding, "Ratios and seeding limits")
                        quick(.recovery, "Retry and recovery status")
                        quick(.log, "Inspect server diagnostics")
                    }
                    if geometry.size.width < 1000 || textSize.isAccessibilitySize { recentActivity }
                }.padding(20).frame(maxWidth: 1440).frame(maxWidth: .infinity)
            }.background(RemoteColors.grouped)
        }.navigationTitle("Overview").refreshable { await model.refresh() }
    }

    private var hero: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Label(model.connected ? "CONNECTED" : "OFFLINE", systemImage: "circle.fill").font(.caption2.bold()).tracking(2)
                Spacer()
                Text(model.platform).font(.caption)
            }.foregroundStyle(.white.opacity(0.75))
            Text(model.selected?.name ?? "Your library, wherever you are.")
                .font(.system(.largeTitle, design: .serif, weight: .semibold)).foregroundStyle(.white)
            HStack(alignment: .firstTextBaseline) {
                Text(model.session.object[model.key("numTorrents", "torrent_count")]?.text ?? String(model.total))
                    .font(.system(size: 58, weight: .light, design: .rounded)).monospacedDigit()
                Text("torrents").font(.headline).foregroundStyle(.white.opacity(0.65))
            }.foregroundStyle(.white)
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 26) { metrics }
                VStack(alignment: .leading, spacing: 16) { metrics }
            }
        }.padding(26).frame(maxWidth: .infinity, alignment: .leading)
            .background(LinearGradient(colors: [ink, Color(red: 0.12, green: 0.35, blue: 0.38)], startPoint: .topLeading, endPoint: .bottomTrailing), in: RoundedRectangle(cornerRadius: 28))
    }
    @ViewBuilder private var metrics: some View {
        metric("DOWNLOAD", value: rate(model.session.object[model.key("downloadRate", "download_rate")]))
        metric("UPLOAD", value: rate(model.session.object[model.key("uploadRate", "upload_rate")]))
        metric("PORT", value: model.session.object[model.key("listenPort", "listen_port")]?.text ?? "--")
    }
    @ViewBuilder private var actions: some View {
        Button("Add Torrents", systemImage: "plus") { workspace.showAdd = true }.disabled(model.client == nil)
        Button("Open Transfers", systemImage: "arrow.down.circle") { workspace.destination = .torrents }
        Button("Notifications", systemImage: "bell") { workspace.destination = .alerts }
        Button("Instances", systemImage: "server.rack") { workspace.showInstances = true }
    }
    private var recentActivity: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack { Text("Recent Activity").font(.headline); Spacer(); Button("All") { workspace.destination = .activity } }
            if model.events.isEmpty { Text("New completions, errors, VPN disconnects, and port changes will appear here.").font(.subheadline).foregroundStyle(.secondary).padding(.vertical, 16) }
            ForEach(model.events.prefix(5)) { event in
                VStack(alignment: .leading, spacing: 4) {
                    Text(event.title).font(.subheadline.bold())
                    Text(event.message).font(.caption).foregroundStyle(.secondary).lineLimit(2)
                    Text(Date(timeIntervalSince1970: event.timestamp), style: .relative).font(.caption2).foregroundStyle(.secondary)
                }
                Divider()
            }
        }.padding(20).frame(maxWidth: .infinity, alignment: .leading).background(RemoteColors.card, in: RoundedRectangle(cornerRadius: 22))
    }
    private func metric(_ title: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title).font(.caption2.bold()).tracking(1.5).foregroundStyle(.white.opacity(0.6))
            Text(value).font(.subheadline.bold()).monospacedDigit().foregroundStyle(.white)
        }.fixedSize(horizontal: true, vertical: false)
    }
    private func quick(_ item: RemoteDestination, _ subtitle: String) -> some View {
        Button { workspace.destination = item } label: {
            VStack(alignment: .leading, spacing: 10) {
                Image(systemName: item.icon).font(.title2).foregroundStyle(sea)
                Text(item.title).font(.headline).foregroundStyle(.primary)
                Text(subtitle).font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            }.frame(maxWidth: .infinity, minHeight: 105, alignment: .topLeading).padding(18)
                .background(RemoteColors.card, in: RoundedRectangle(cornerRadius: 20))
        }.buttonStyle(.plain)
    }
}

struct TorrentsView: View {
    @Environment(RemoteModel.self) private var model
    @Environment(RemoteWorkspace.self) private var workspace
    @Environment(\.dynamicTypeSize) private var textSize
    private var sorted: [RemoteTorrent] { model.torrents.sorted(using: workspace.sortOrder) }
    var body: some View {
        @Bindable var model = model
        @Bindable var workspace = workspace
        GeometryReader { geometry in
            VStack(spacing: 0) {
                ViewThatFits(in: .horizontal) {
                    HStack(spacing: 16) { filters }
                    VStack(alignment: .leading, spacing: 10) { filters }
                }.padding(12).background(.bar)
                if RemoteLayout.usesTable(width: geometry.size.width, accessibilityText: textSize.isAccessibilitySize) {
                    torrentTable
                } else {
                    torrentList
                }
                pagination
            }
        }
        .navigationTitle("Torrents").searchable(text: $model.search, prompt: "Name or hash")
        .task(id: model.search) {
            try? await Task.sleep(for: .milliseconds(300))
            if !Task.isCancelled && model.search != model.appliedSearch { workspace.selectedHashes = []; await model.changeFilter() }
        }
        .onChange(of: model.category) { _, _ in workspace.selectedHashes = []; Task { await model.changeFilter() } }
        .onChange(of: model.torrents) { _, values in workspace.reconcile(with: values) }
        .refreshable { await model.refresh() }
        .toolbar {
            ToolbarItemGroup(placement: .automatic) {
                Button(workspace.selecting ? "Done" : "Select", systemImage: "checkmark.circle") { workspace.selecting.toggle() }
                Button("Add", systemImage: "plus") { workspace.showAdd = true }.disabled(model.client == nil)
                Button("Inspector", systemImage: "sidebar.right") { workspace.showInspector.toggle() }.help("Show torrent inspector")
            }
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            if !workspace.selectedHashes.isEmpty {
                ViewThatFits(in: .horizontal) {
                    HStack(spacing: 12) { bulkActions }
                    VStack(alignment: .leading, spacing: 12) { bulkActions }
                }.padding(12).frame(maxWidth: .infinity, alignment: .leading).background(.bar)
            }
        }
        .inspector(isPresented: $workspace.showInspector) {
            NavigationStack {
                Group {
                    if workspace.selectedHashes.count == 1, let torrent = model.torrents.first(where: { workspace.selectedHashes.contains($0.hash) }) {
                        TorrentDetail(torrent: torrent).id("\(model.selectedID?.uuidString ?? "")-\(torrent.hash)")
                    } else {
                        ContentUnavailableView(workspace.selectedHashes.isEmpty ? "Select a Torrent" : "\(workspace.selectedHashes.count) Selected", systemImage: "sidebar.right", description: Text("Select one torrent to inspect files, trackers, and peers. Use the selection bar to control multiple torrents."))
                    }
                }.toolbar { if workspace.showInspector { Button("Close") { workspace.showInspector = false } } }
            }.inspectorColumnWidth(min: 300, ideal: 360, max: 480)
        }
        .remoteDeleteCommand { if !workspace.selectedHashes.isEmpty && !model.busy { workspace.confirmDelete = true } }
        .confirmationDialog("Remove \(workspace.selectedHashes.count) torrent(s)?", isPresented: $workspace.confirmDelete, titleVisibility: .visible) {
            Button("Remove from Controllarr (Keep Files)") { remove(false) }
            Button("Remove and Delete Files from Server", role: .destructive) { remove(true) }
            Button("Cancel", role: .cancel) { }
        } message: { Text("Disk deletion happens on \(model.selected?.name ?? "the selected server") and cannot be undone.") }
    }

    @ViewBuilder private var filters: some View {
        @Bindable var model = model
        Picker("Category", selection: $model.category) {
            Text("All Categories").tag(String?.none)
            Text("Uncategorized").tag(Optional(""))
            ForEach(model.categoryNames, id: \.self) { Text($0).tag(Optional($0)) }
        }.frame(maxWidth: 360)
        Button(workspace.selectedHashes.count == model.torrents.count && !model.torrents.isEmpty ? "Deselect Page" : "Select Page") {
            workspace.selectedHashes = workspace.selectedHashes.count == model.torrents.count ? [] : Set(model.torrents.map(\.hash))
        }.disabled(model.torrents.isEmpty)
        if model.refreshing { ProgressView().controlSize(.small).accessibilityLabel("Refreshing") }
    }

    private var torrentTable: some View {
        @Bindable var workspace = workspace
        return Table(sorted, selection: $workspace.selectedHashes, sortOrder: $workspace.sortOrder) {
            TableColumn("Name", value: \.name) { torrent in
                VStack(alignment: .leading, spacing: 3) {
                    Text(torrent.name.isEmpty ? torrent.hash : torrent.name).lineLimit(1)
                    if !torrent.category.isEmpty { Text(torrent.category).font(.caption2).foregroundStyle(sea) }
                }.help(torrent.name)
            }.width(min: 180, ideal: 330)
            TableColumn("Progress", value: \.progress) { torrent in
                VStack(alignment: .leading, spacing: 3) { ProgressView(value: torrent.progress).tint(sea); Text(torrent.progress, format: .percent.precision(.fractionLength(0))).font(.caption2).monospacedDigit() }
            }.width(min: 80, ideal: 100, max: 130)
            TableColumn("Download", value: \.dlspeed) { Text(ByteCountFormatter.string(fromByteCount: $0.dlspeed, countStyle: .binary) + "/s").monospacedDigit() }.width(min: 85, ideal: 100, max: 130)
            TableColumn("Upload", value: \.upspeed) { Text(ByteCountFormatter.string(fromByteCount: $0.upspeed, countStyle: .binary) + "/s").monospacedDigit() }.width(min: 85, ideal: 100, max: 130)
            TableColumn("State", value: \.state).width(min: 100, ideal: 120, max: 160)
        }
        .contextMenu(forSelectionType: String.self) { hashes in
            Button("Inspect") { workspace.selectedHashes = hashes; workspace.showInspector = true }.disabled(hashes.isEmpty)
            Button("Pause") { run("pause", hashes) }.disabled(hashes.isEmpty || model.busy)
            Button("Resume") { run("resume", hashes) }.disabled(hashes.isEmpty || model.busy)
            Button("Remove...", role: .destructive) { workspace.selectedHashes = hashes; workspace.confirmDelete = true }.disabled(hashes.isEmpty || model.busy)
        } primaryAction: { hashes in workspace.selectedHashes = hashes; workspace.showInspector = true }
        .overlay { if model.torrents.isEmpty { emptyState } }
    }
    private var torrentList: some View {
        List {
            ForEach(sorted) { torrent in
                Button {
                    if workspace.selecting {
                        if !workspace.selectedHashes.insert(torrent.hash).inserted { workspace.selectedHashes.remove(torrent.hash) }
                    } else { workspace.inspect(torrent.hash) }
                } label: {
                    HStack {
                        if workspace.selecting { Image(systemName: workspace.selectedHashes.contains(torrent.hash) ? "checkmark.circle.fill" : "circle").foregroundStyle(sea) }
                        TorrentRow(torrent: torrent)
                    }.contentShape(Rectangle())
                }.buttonStyle(.plain)
                    .contextMenu {
                        Button("Inspect") { workspace.inspect(torrent.hash) }
                        Button("Pause") { run("pause", [torrent.hash]) }
                        Button("Resume") { run("resume", [torrent.hash]) }
                        Button("Remove...", role: .destructive) { workspace.selectedHashes = [torrent.hash]; workspace.confirmDelete = true }
                    }
            }
        }.overlay { if model.torrents.isEmpty { emptyState } }
    }
    private var emptyState: some View {
        ContentUnavailableView(model.connected ? "No Matching Torrents" : "Connect a Server", systemImage: "arrow.down.circle", description: Text(model.connected ? "Try another search or category, or add a torrent." : "Choose an instance to manage its transfers."))
    }
    private var pagination: some View {
        VStack(spacing: 6) {
            HStack {
                Button { page(-1) } label: { Label("Previous", systemImage: "chevron.left") }.disabled(model.offset == 0 || model.refreshing)
                Spacer(minLength: 8)
                Text("\(model.total == 0 ? 0 : min(model.offset + 1, model.total))-\(min(model.offset + RemotePageRequest.limit, model.total)) of \(model.total)").font(.caption).monospacedDigit()
                Spacer(minLength: 8)
                Button { page(1) } label: { Label("Next", systemImage: "chevron.right") }.disabled(model.offset + RemotePageRequest.limit >= model.total || model.refreshing)
            }
            Text("100 per page. Column sorting applies to this page.").font(.caption2).foregroundStyle(.secondary)
        }.padding(12).background(.bar)
    }
    @ViewBuilder private var bulkActions: some View {
        Text("\(workspace.selectedHashes.count) selected").font(.caption.bold()).monospacedDigit()
        HStack(spacing: 16) {
            Button { run("pause", workspace.selectedHashes) } label: { Label("Pause", systemImage: "pause") }
            Button { run("resume", workspace.selectedHashes) } label: { Label("Resume", systemImage: "play") }
            Menu {
                Button("Uncategorized") { setCategory("") }
                ForEach(model.categoryNames, id: \.self) { name in Button(name) { setCategory(name) } }
            } label: { Label("Category", systemImage: "folder") }
            Button(role: .destructive) { workspace.confirmDelete = true } label: { Label("Remove", systemImage: "trash") }
        }.disabled(model.busy || model.client == nil)
    }
    private func page(_ delta: Int) {
        model.offset = min(RemotePageRequest.lastOffset(total: model.total), max(0, model.offset + delta * RemotePageRequest.limit))
        workspace.selectedHashes = []
        Task { await model.refresh() }
    }
    private func run(_ action: String, _ hashes: Set<String>) { Task { await model.action(action, hashes: hashes) } }
    private func setCategory(_ name: String) {
        let hashes = workspace.selectedHashes
        Task { await model.action("setCategory", hashes: hashes, extra: ["category": name]) }
    }
    private func remove(_ files: Bool) {
        let hashes = workspace.selectedHashes
        workspace.selectedHashes = []
        Task { await model.action("delete", hashes: hashes, extra: ["deleteFiles": String(files)]) }
    }
}
