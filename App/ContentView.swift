//
//  ContentView.swift
//  Controllarr — Phase 2
//
//  Native main window. NavigationSplitView with sidebar tabs for
//  Torrents, Categories, Settings, Health, Post-Processing, Seeding and
//  the log viewer. All tabs bind to the shared RuntimeViewModel.
//

import SwiftUI
import UniformTypeIdentifiers
import TorrentEngine
import Persistence
import Services

enum Tab: String, CaseIterable, Identifiable {
    case torrents, categories, settings, health, recovery, postProcessor, seeding, arr, log
    var id: String { rawValue }

    var title: String {
        switch self {
        case .torrents:      return "Torrents"
        case .categories:    return "Categories"
        case .settings:      return "Settings"
        case .health:        return "Health"
        case .recovery:      return "Recovery"
        case .postProcessor: return "Post-Processor"
        case .seeding:       return "Seeding"
        case .arr:           return "*arr Activity"
        case .log:           return "Log"
        }
    }

    var systemImage: String {
        switch self {
        case .torrents:      return "arrow.up.arrow.down"
        case .categories:    return "folder"
        case .settings:      return "gearshape"
        case .health:        return "heart.text.square"
        case .recovery:      return "arrow.counterclockwise"
        case .postProcessor: return "shippingbox"
        case .seeding:       return "leaf"
        case .arr:           return "antenna.radiowaves.left.and.right"
        case .log:           return "text.alignleft"
        }
    }
}

struct ContentView: View {
    @State private var vm = RuntimeViewModel.shared
    @State private var selection: Tab = .torrents

    var body: some View {
        NavigationSplitView {
            List(Tab.allCases, selection: $selection) { tab in
                Label(tab.title, systemImage: tab.systemImage)
                    .tag(tab)
            }
            .navigationSplitViewColumnWidth(min: 160, ideal: 180)
        } detail: {
            Group {
                if vm.isBooting {
                    VStack(spacing: 12) {
                        ProgressView()
                        Text("Starting Controllarr runtime…")
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if let err = vm.bootError {
                    VStack(spacing: 12) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .font(.largeTitle)
                            .foregroundStyle(.orange)
                        Text("Failed to start").font(.title2)
                        Text(err).font(.callout).foregroundStyle(.secondary)
                            .textSelection(.enabled)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    switch selection {
                    case .torrents:      TorrentsView(vm: vm)
                    case .categories:    CategoriesView(vm: vm)
                    case .settings:      SettingsView(vm: vm)
                    case .health:        HealthView(vm: vm)
                    case .recovery:      RecoveryView(vm: vm)
                    case .postProcessor: PostProcessorView(vm: vm)
                    case .seeding:       SeedingView(vm: vm)
                    case .arr:           ArrView(vm: vm)
                    case .log:           LogView(vm: vm)
                    }
                }
            }
            .navigationTitle(selection.title)
            .toolbar {
                ToolbarItemGroup(placement: .principal) {
                    SessionStatusBar(vm: vm)
                }
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        vm.openWebUI()
                    } label: {
                        Label("Web UI", systemImage: "safari")
                    }
                    .help("Open the browser-facing WebUI")
                }
            }
        }
        .frame(minWidth: 900, minHeight: 560)
        .task {
            await vm.boot()
        }
    }
}

// MARK: - Session status bar

private struct SessionStatusBar: View {
    let vm: RuntimeViewModel
    var body: some View {
        HStack(spacing: 8) {
            // Connection indicator + port
            HStack(spacing: 4) {
                Image(systemName: "circle.fill")
                    .font(.system(size: 6))
                    .foregroundStyle(vm.session.hasIncomingConnections ? .green : .orange)
                Text("\(vm.session.listenPort)")
                    .font(.caption.monospacedDigit())
            }

            Divider().frame(height: 12)

            // Transfer rates
            Text("↓ \(formatRate(vm.session.downloadRate))")
                .font(.caption.monospacedDigit())
                .foregroundStyle(.blue)
            Text("↑ \(formatRate(vm.session.uploadRate))")
                .font(.caption.monospacedDigit())
                .foregroundStyle(.green)

            Divider().frame(height: 12)

            Text("\(vm.session.numTorrents)")
                .font(.caption.monospacedDigit())
                .foregroundStyle(.secondary)
            + Text(" torrents")
                .font(.caption)
                .foregroundStyle(.secondary)

            // VPN pill
            if let vpn = vm.vpnStatus, vm.settings.vpnEnabled {
                Divider().frame(height: 12)
                HStack(spacing: 3) {
                    Image(systemName: vpn.isConnected ? "lock.shield.fill" : "lock.shield")
                        .font(.system(size: 9))
                    Text(vpn.isConnected
                         ? (vpn.interfaceName ?? "VPN")
                         : "VPN down")
                        .font(.caption2)
                }
                .padding(.horizontal, 5)
                .padding(.vertical, 2)
                .background(
                    (vpn.isConnected ? Color.green : Color.red).opacity(0.15),
                    in: RoundedRectangle(cornerRadius: 4)
                )
                .foregroundStyle(vpn.isConnected ? .green : .red)
            }

            // Disk pressure pill
            if let ds = vm.diskSpaceStatus, ds.isPaused {
                HStack(spacing: 3) {
                    Image(systemName: "externaldrive.badge.exclamationmark")
                        .font(.system(size: 9))
                    Text("Low disk")
                        .font(.caption2)
                }
                .padding(.horizontal, 5)
                .padding(.vertical, 2)
                .background(Color.orange.opacity(0.15), in: RoundedRectangle(cornerRadius: 4))
                .foregroundStyle(.orange)
            }
        }
        .fixedSize()
    }
}

// MARK: - Torrents tab

/// Status groupings the operator can dropdown-filter on. Matches the nested
/// set Everett requested: All, Downloading, Seeding, Completed, Running,
/// Stopped, Active, Inactive, Stalled, Moving, Errored.
enum TorrentStatusFilter: String, CaseIterable, Identifiable {
    case all, downloading, seeding, completed, running, stopped
    case active, inactive, stalled, moving, errored

    var id: String { rawValue }

    var title: String {
        switch self {
        case .all:         return "All"
        case .downloading: return "Downloading"
        case .seeding:     return "Seeding"
        case .completed:   return "Completed"
        case .running:     return "Running"
        case .stopped:     return "Stopped"
        case .active:      return "Active"
        case .inactive:    return "Inactive"
        case .stalled:     return "Stalled"
        case .moving:      return "Moving"
        case .errored:     return "Errored"
        }
    }

    func matches(_ t: TorrentStats) -> Bool {
        switch self {
        case .all:         return true
        case .downloading: return !t.paused && t.state == .downloading
        case .seeding:     return !t.paused && t.state == .seeding
        case .completed:   return t.progress >= 1.0
        case .running:     return !t.paused
        case .stopped:     return t.paused
        case .active:      return t.downloadRate > 0 || t.uploadRate > 0
        case .inactive:    return t.downloadRate == 0 && t.uploadRate == 0
        case .stalled:
            // No peers and not paused, or no data movement for a downloading item.
            return !t.paused && t.numPeers == 0 && t.state == .downloading
        case .moving:      return t.state == .checkingFiles || t.state == .checkingResume
        case .errored:
            // No engine error field yet — approximate with "stopped while < 100%".
            return t.paused && t.progress < 1.0
        }
    }
}

struct TorrentsView: View {
    @Bindable var vm: RuntimeViewModel
    @State private var addOpen = false
    @State private var magnetURI = ""
    @State private var addCategory: String = ""
    @State private var addError: String?
    @State private var selectedHash: String?
    @State private var dropTargeted = false
    @State private var statusFilter: TorrentStatusFilter = .all
    /// Empty string = "All Categories".
    /// "__none__" sentinel = "Uncategorized only".
    /// Any other value = exact category-name match.
    @State private var categoryFilter: String = ""
    @State private var sortOrder: [KeyPathComparator<TorrentStats>] = [
        KeyPathComparator(\.name, order: .forward)
    ]
    @State private var showCategorySheet = false
    /// Column widths and ordering persist across launches via @SceneStorage.
    @SceneStorage("TorrentsTable.columnCustomization")
    private var columnCustomization: TableColumnCustomization<TorrentStats>

    /// Sentinel value used in the picker for "Uncategorized". Kept out of
    /// the valid-category namespace so it can never collide with a real
    /// user-defined category.
    private static let uncategorizedTag = "__none__"

    private func matchesCategoryFilter(_ t: TorrentStats) -> Bool {
        switch categoryFilter {
        case "":                          return true
        case Self.uncategorizedTag:       return (t.category ?? "").isEmpty
        default:                          return (t.category ?? "") == categoryFilter
        }
    }

    private var filteredSortedTorrents: [TorrentStats] {
        vm.torrents
            .filter { statusFilter.matches($0) && matchesCategoryFilter($0) }
            .sorted(using: sortOrder)
    }

    var body: some View {
        VSplitView {
            VStack(spacing: 0) {
                // Filter toolbar
                HStack(spacing: 8) {
                    Image(systemName: "line.3.horizontal.decrease.circle")
                        .foregroundStyle(.secondary)
                    Picker("Status", selection: $statusFilter) {
                        ForEach(TorrentStatusFilter.allCases) { f in
                            Text(f.title).tag(f)
                        }
                    }
                    .pickerStyle(.menu)
                    .frame(maxWidth: 180)
                    .onChange(of: statusFilter) { _, new in
                        var s = vm.settings
                        s.uiPreferences.torrentStatusFilter = new.rawValue
                        Task { await vm.saveSettings(s) }
                    }

                    Picker("Category", selection: $categoryFilter) {
                        Text("All Categories").tag("")
                        Text("Uncategorized").tag(Self.uncategorizedTag)
                        if !vm.categories.isEmpty {
                            Divider()
                            ForEach(vm.categories.map(\.name).sorted(), id: \.self) { name in
                                Text(name).tag(name)
                            }
                        }
                    }
                    .pickerStyle(.menu)
                    .frame(maxWidth: 200)
                    .onChange(of: categoryFilter) { _, new in
                        var s = vm.settings
                        s.uiPreferences.torrentCategoryFilter = new
                        Task { await vm.saveSettings(s) }
                    }

                    Spacer()
                    Text("\(filteredSortedTorrents.count) of \(vm.torrents.count)")
                        .font(.caption).foregroundStyle(.secondary)
                }
                .padding(.horizontal, 8).padding(.top, 6).padding(.bottom, 2)

                Table(
                    filteredSortedTorrents,
                    selection: $selectedHash,
                    sortOrder: $sortOrder,
                    columnCustomization: $columnCustomization
                ) {
                    TableColumn("Name", value: \.name) { t in
                        Text(t.name).lineLimit(1).truncationMode(.middle)
                    }
                    .customizationID("name")
                    TableColumn("Size", value: \.totalWanted) { t in
                        Text(formatBytes(t.totalWanted)).monospacedDigit()
                    }.width(min: 80, ideal: 90).customizationID("size")
                    TableColumn("Progress", value: \.progress) { t in
                        VStack(alignment: .leading, spacing: 2) {
                            ProgressView(value: Double(t.progress))
                                .progressViewStyle(.linear)
                                .frame(width: 110)
                            Text(String(format: "%.0f%%", t.progress * 100))
                                .font(.caption.monospacedDigit())
                                .foregroundStyle(.secondary)
                        }
                    }.width(min: 120, ideal: 140).customizationID("progress")
                    TableColumn("State") { t in
                        Text(t.paused ? "paused" : "\(t.state)")
                            .font(.caption)
                            .foregroundStyle(t.paused ? .orange : .primary)
                    }.width(min: 70, ideal: 90).customizationID("state")
                    TableColumn("↓", value: \.downloadRate) { t in
                        Text(formatRate(t.downloadRate)).monospacedDigit().font(.caption)
                    }.width(min: 70, ideal: 80).customizationID("down")
                    TableColumn("↑", value: \.uploadRate) { t in
                        Text(formatRate(t.uploadRate)).monospacedDigit().font(.caption)
                    }.width(min: 70, ideal: 80).customizationID("up")
                    TableColumn("Peers", value: \.numPeers) { t in
                        Text("\(t.numPeers)").monospacedDigit().font(.caption)
                    }.width(min: 50, ideal: 60).customizationID("peers")
                    TableColumn("Ratio", value: \.ratio) { t in
                        Text(String(format: "%.2f", t.ratio)).monospacedDigit().font(.caption)
                    }.width(min: 55, ideal: 65).customizationID("ratio")
                    TableColumn("Category") { t in
                        Text(t.category ?? "—").font(.caption).foregroundStyle(.secondary)
                    }.width(min: 80, ideal: 100).customizationID("category")
                }
                .onAppear {
                    // Hydrate persisted filters on first load.
                    if let restored = TorrentStatusFilter(
                        rawValue: vm.settings.uiPreferences.torrentStatusFilter
                    ) {
                        statusFilter = restored
                    }
                    categoryFilter = vm.settings.uiPreferences.torrentCategoryFilter
                }

                Divider()
                HStack(spacing: 8) {
                    Button {
                        magnetURI = ""
                        addCategory = ""
                        addError = nil
                        addOpen = true
                    } label: {
                        Label("Add Magnet", systemImage: "plus")
                    }

                    Button {
                        openTorrentFilePicker()
                    } label: {
                        Label("Add .torrent", systemImage: "doc.badge.plus")
                    }

                    if let hash = selectedHash, let t = vm.torrents.first(where: { $0.infoHash == hash }) {
                        Button {
                            Task { t.paused ? await vm.resume(hash: hash) : await vm.pause(hash: hash) }
                        } label: {
                            Label(t.paused ? "Resume" : "Pause", systemImage: t.paused ? "play.fill" : "pause.fill")
                        }

                        Button {
                            Task { await vm.reannounce(hash: hash) }
                        } label: {
                            Label("Reannounce", systemImage: "arrow.clockwise")
                        }

                        Menu {
                            Button("Remove torrent (keep files)") {
                                Task { await vm.remove(hash: hash, deleteFiles: false) }
                            }
                            Button("Remove torrent and delete files", role: .destructive) {
                                Task { await vm.remove(hash: hash, deleteFiles: true) }
                            }
                        } label: {
                            Label("Remove", systemImage: "trash")
                        }
                    }

                    Spacer()
                    Text("\(vm.torrents.count) total")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .padding(8)
            }
            .frame(minHeight: 200)

            // Detail pane — files / trackers / peers
            if let hash = selectedHash,
               vm.torrents.contains(where: { $0.infoHash == hash }) {
                TorrentDetailPane(vm: vm, hash: hash)
                    .frame(minHeight: 180, idealHeight: 260)
            }
        }
        .overlay {
            if dropTargeted {
                ZStack {
                    RoundedRectangle(cornerRadius: 12)
                        .fill(.blue.opacity(0.08))
                    RoundedRectangle(cornerRadius: 12)
                        .strokeBorder(.blue, style: StrokeStyle(lineWidth: 2, dash: [8, 4]))
                    VStack(spacing: 8) {
                        Image(systemName: "doc.badge.plus")
                            .font(.system(size: 36))
                            .foregroundStyle(.blue)
                        Text("Drop .torrent files here")
                            .font(.title3).foregroundStyle(.blue)
                    }
                }
                .padding(4)
                .allowsHitTesting(false)
            }
        }
        .onDrop(of: [.fileURL], isTargeted: $dropTargeted) { providers in
            handleDrop(providers)
        }
        .sheet(isPresented: $addOpen) {
            addMagnetSheet
                .frame(minWidth: 460, minHeight: 220)
        }
    }

    private func handleDrop(_ providers: [NSItemProvider]) -> Bool {
        var handled = false
        for provider in providers {
            if provider.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier) {
                handled = true
                provider.loadItem(forTypeIdentifier: UTType.fileURL.identifier, options: nil) { item, _ in
                    guard let data = item as? Data,
                          let url = URL(dataRepresentation: data, relativeTo: nil),
                          url.pathExtension.lowercased() == "torrent" else { return }
                    Task { @MainActor in
                        do {
                            try await vm.addTorrentFile(at: url, category: nil)
                        } catch {
                            NSLog("[Controllarr] Drop add failed: \(error)")
                        }
                    }
                }
            }
        }
        return handled
    }

    private func openTorrentFilePicker() {
        let panel = NSOpenPanel()
        panel.title = "Select .torrent files"
        panel.allowedContentTypes = [
            UTType(filenameExtension: "torrent") ?? .data
        ]
        panel.allowsMultipleSelection = true
        panel.canChooseDirectories = false
        panel.begin { response in
            guard response == .OK else { return }
            for url in panel.urls {
                Task {
                    do {
                        try await vm.addTorrentFile(at: url, category: nil)
                    } catch {
                        NSLog("[Controllarr] File picker add failed: \(error)")
                    }
                }
            }
        }
    }

    private var addMagnetSheet: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Add Magnet").font(.title3).bold()
            TextField("magnet:?xt=urn:btih:…", text: $magnetURI, axis: .vertical)
                .lineLimit(3...6)
                .textFieldStyle(.roundedBorder)
            Picker("Category", selection: $addCategory) {
                Text("— none —").tag("")
                ForEach(vm.categories) { c in
                    Text(c.name).tag(c.name)
                }
            }
            if let addError {
                Text(addError).font(.caption).foregroundStyle(.red)
            }
            HStack {
                Spacer()
                Button("Cancel") { addOpen = false }
                Button("Add") {
                    let uri = magnetURI.trimmingCharacters(in: .whitespacesAndNewlines)
                    guard !uri.isEmpty else { return }
                    let cat = addCategory.isEmpty ? nil : addCategory
                    Task {
                        do {
                            try await vm.addMagnet(uri, category: cat)
                            addOpen = false
                        } catch {
                            addError = "\(error)"
                        }
                    }
                }
                .keyboardShortcut(.defaultAction)
                .disabled(magnetURI.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .padding(18)
    }
}

// MARK: - Torrent detail pane (Files / Trackers / Peers)

enum DetailTab: String, CaseIterable, Identifiable {
    case files, trackers, peers
    var id: String { rawValue }
    var title: String { rawValue.capitalized }
}

struct TorrentDetailPane: View {
    @Bindable var vm: RuntimeViewModel
    let hash: String
    @State private var tab: DetailTab = .files
    @State private var files: [FileInfo] = []
    @State private var trackerList: [TrackerInfo] = []
    @State private var peerList: [PeerInfo] = []

    var body: some View {
        VStack(spacing: 0) {
            Picker("Detail", selection: $tab) {
                ForEach(DetailTab.allCases) { t in
                    Text(t.title).tag(t)
                }
            }
            .pickerStyle(.segmented)
            .padding(.horizontal, 8)
            .padding(.top, 6)

            switch tab {
            case .files:    filesTable
            case .trackers: trackersTable
            case .peers:    peersTable
            }
        }
        .task(id: hash) { await loadAll() }
        .task(id: tab)  { await loadAll() }
    }

    private func loadAll() async {
        files = await vm.fileInfo(for: hash)
        trackerList = await vm.trackers(for: hash)
        peerList = await vm.peers(for: hash)
    }

    private var filesTable: some View {
        VStack(spacing: 0) {
            if files.isEmpty {
                Text("Waiting for metadata…")
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                Table(files) {
                    TableColumn("File") { f in
                        Text(f.name).lineLimit(1).truncationMode(.middle).font(.caption)
                    }
                    TableColumn("Size") { f in
                        Text(formatBytes(f.size)).monospacedDigit().font(.caption)
                    }.width(min: 80, ideal: 90)
                    TableColumn("Priority") { f in
                        Text(priorityLabel(f.priority))
                            .font(.caption)
                            .foregroundStyle(f.priority == 0 ? .red : .primary)
                    }.width(min: 90, ideal: 110)
                    TableColumn("") { f in
                        Button(f.priority == 0 ? "Enable" : "Skip") {
                            Task { await toggleFile(f) }
                        }
                        .font(.caption)
                    }.width(min: 60, ideal: 70)
                }
            }
        }
    }

    private func priorityLabel(_ p: Int) -> String {
        switch p {
        case 0: return "Skip"
        case 1: return "Normal"
        case 4: return "Normal"
        case 7: return "High"
        default: return "Prio \(p)"
        }
    }

    private func toggleFile(_ f: FileInfo) async {
        var priorities = files.map(\.priority)
        priorities[f.index] = (f.priority == 0) ? 4 : 0
        _ = await vm.setFilePriorities(priorities, for: hash)
        files = await vm.fileInfo(for: hash)
    }

    private var trackersTable: some View {
        Group {
            if trackerList.isEmpty {
                Text("No trackers")
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                Table(trackerList) {
                    TableColumn("URL") { t in
                        Text(t.url).lineLimit(1).truncationMode(.middle).font(.caption)
                    }
                    TableColumn("Status") { t in
                        Text(trackerStatus(t.status))
                            .font(.caption)
                            .foregroundStyle(t.status == 4 ? .red : t.status == 2 ? .green : .secondary)
                    }.width(min: 90, ideal: 110)
                    TableColumn("Seeds") { t in
                        Text("\(t.numSeeds)").monospacedDigit().font(.caption)
                    }.width(min: 50, ideal: 60)
                    TableColumn("Peers") { t in
                        Text("\(t.numPeers)").monospacedDigit().font(.caption)
                    }.width(min: 50, ideal: 60)
                    TableColumn("Message") { t in
                        Text(t.message).lineLimit(1).font(.caption).foregroundStyle(.secondary)
                    }
                }
            }
        }
    }

    private func trackerStatus(_ s: Int) -> String {
        switch s {
        case 0: return "Disabled"
        case 1: return "Not contacted"
        case 2: return "Working"
        case 3: return "Updating"
        case 4: return "Error"
        default: return "Unknown"
        }
    }

    private var peersTable: some View {
        Group {
            if peerList.isEmpty {
                Text("No peers connected")
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                Table(peerList) {
                    TableColumn("IP") { p in
                        Text(p.ip).font(.caption.monospaced())
                    }.width(min: 120, ideal: 140)
                    TableColumn("Client") { p in
                        Text(p.client).lineLimit(1).font(.caption)
                    }.width(min: 140, ideal: 180)
                    TableColumn("Progress") { p in
                        Text(String(format: "%.0f%%", p.progress * 100)).monospacedDigit().font(.caption)
                    }.width(min: 60, ideal: 70)
                    TableColumn("↓") { p in
                        Text(formatRate(p.downloadRate)).monospacedDigit().font(.caption)
                    }.width(min: 70, ideal: 80)
                    TableColumn("↑") { p in
                        Text(formatRate(p.uploadRate)).monospacedDigit().font(.caption)
                    }.width(min: 70, ideal: 80)
                    TableColumn("Flags") { p in
                        Text(p.flags).font(.caption.monospaced()).foregroundStyle(.secondary)
                    }.width(min: 60, ideal: 70)
                }
            }
        }
    }
}

// MARK: - Categories tab

struct CategoriesView: View {
    @Bindable var vm: RuntimeViewModel
    @State private var editing: Persistence.Category?
    @State private var selectedName: String?
    @State private var pendingPathChange: PendingCategoryPathChange?

    /// Payload for the "move existing torrents to new path?" confirmation.
    struct PendingCategoryPathChange: Identifiable {
        let id = UUID()
        let category: String
        let newPath: String
    }

    var body: some View {
        HSplitView {
            VStack(spacing: 0) {
                List(vm.categories, selection: $selectedName) { c in
                    VStack(alignment: .leading, spacing: 2) {
                        Text(c.name).bold()
                        Text(c.savePath).font(.caption).foregroundStyle(.secondary)
                            .lineLimit(1).truncationMode(.middle)
                    }
                    .tag(c.name)
                }
                Divider()
                HStack {
                    Button {
                        editing = Persistence.Category(name: "", savePath: vm.settings.defaultSavePath)
                    } label: { Label("New", systemImage: "plus") }
                    if let name = selectedName, let cat = vm.categories.first(where: { $0.name == name }) {
                        Button {
                            editing = cat
                        } label: { Label("Edit", systemImage: "pencil") }
                        Button(role: .destructive) {
                            Task { await vm.deleteCategory(named: name) }
                        } label: { Label("Delete", systemImage: "trash") }
                    }
                    Spacer()
                }
                .padding(8)
            }
            .frame(minWidth: 240)

            if let name = selectedName, let cat = vm.categories.first(where: { $0.name == name }) {
                CategoryDetail(category: cat, vm: vm)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                Text("Select or create a category")
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .sheet(item: $editing) { cat in
            CategoryEditor(original: cat) { updated in
                Task {
                    let existing = vm.categories.first(where: { $0.name == updated.name })
                    let pathChanged = existing != nil
                        && existing!.savePath != updated.savePath
                        && !updated.savePath.isEmpty
                    await vm.saveCategory(updated)
                    editing = nil
                    if pathChanged {
                        pendingPathChange = PendingCategoryPathChange(
                            category: updated.name, newPath: updated.savePath
                        )
                    }
                }
            } onCancel: {
                editing = nil
            }
            .frame(minWidth: 520, minHeight: 460)
        }
        .alert(
            "Move existing torrents to new location?",
            isPresented: Binding(
                get: { pendingPathChange != nil },
                set: { if !$0 { pendingPathChange = nil } }
            ),
            presenting: pendingPathChange
        ) { change in
            Button("Move files") {
                Task {
                    _ = await vm.applyCategoryPathChange(
                        category: change.category,
                        newPath: change.newPath,
                        moveFiles: true
                    )
                    pendingPathChange = nil
                }
            }
            Button("Leave them", role: .cancel) {
                pendingPathChange = nil
            }
        } message: { change in
            Text("Torrents tagged \"\(change.category)\" will be moved to \(change.newPath). This runs libtorrent's storage move in the background — the files stay available during the copy.")
        }
    }
}

private struct CategoryDetail: View {
    let category: Persistence.Category
    @Bindable var vm: RuntimeViewModel
    @State private var statusFilter: TorrentStatusFilter = .all

    private var categoryTorrents: [TorrentStats] {
        vm.torrents
            .filter { ($0.category ?? "") == category.name && statusFilter.matches($0) }
    }

    var body: some View {
        VSplitView {
            Form {
                LabeledContent("Save path", value: category.savePath)
                if let cp = category.completePath, !cp.isEmpty {
                    LabeledContent("Complete path", value: cp)
                }
                LabeledContent("Extract archives", value: category.extractArchives ? "yes" : "no")
                LabeledContent("Blocked extensions", value: category.blockedExtensions.isEmpty ? "—" : category.blockedExtensions.joined(separator: ", "))
                if let r = category.maxRatio {
                    LabeledContent("Max ratio", value: String(format: "%.2f", r))
                }
                if let m = category.maxSeedingTimeMinutes {
                    LabeledContent("Max seed time", value: "\(m) min")
                }
            }
            .formStyle(.grouped)
            .frame(minHeight: 120, idealHeight: 200)

            // Torrents in this category, with the same status filter as the
            // main Torrents tab.
            VStack(spacing: 0) {
                HStack(spacing: 8) {
                    Image(systemName: "line.3.horizontal.decrease.circle")
                        .foregroundStyle(.secondary)
                    Picker("Status", selection: $statusFilter) {
                        ForEach(TorrentStatusFilter.allCases) { f in
                            Text(f.title).tag(f)
                        }
                    }
                    .pickerStyle(.menu)
                    .frame(maxWidth: 180)
                    Spacer()
                    Text("\(categoryTorrents.count) torrents")
                        .font(.caption).foregroundStyle(.secondary)
                }
                .padding(.horizontal, 8).padding(.top, 6).padding(.bottom, 2)

                Table(categoryTorrents) {
                    TableColumn("Name") { t in
                        Text(t.name).lineLimit(1).truncationMode(.middle)
                    }
                    TableColumn("State") { t in
                        Text(t.paused ? "paused" : "\(t.state)")
                            .font(.caption)
                            .foregroundStyle(t.paused ? .orange : .primary)
                    }.width(min: 70, ideal: 90)
                    TableColumn("Progress") { t in
                        Text(String(format: "%.0f%%", t.progress * 100))
                            .monospacedDigit().font(.caption)
                    }.width(min: 70, ideal: 80)
                    TableColumn("↓") { t in
                        Text(formatRate(t.downloadRate)).monospacedDigit().font(.caption)
                    }.width(min: 70, ideal: 80)
                    TableColumn("↑") { t in
                        Text(formatRate(t.uploadRate)).monospacedDigit().font(.caption)
                    }.width(min: 70, ideal: 80)
                    TableColumn("Ratio") { t in
                        Text(String(format: "%.2f", t.ratio)).monospacedDigit().font(.caption)
                    }.width(min: 55, ideal: 65)
                }
            }
            .frame(minHeight: 180)
        }
    }
}

private struct CategoryEditor: View {
    @State var name: String
    @State var savePath: String
    @State var completePath: String
    @State var extractArchives: Bool
    @State var blockedExtensions: String
    @State var hasMaxRatio: Bool
    @State var maxRatio: Double
    @State var hasMaxSeedTime: Bool
    @State var maxSeedTimeMinutes: Int
    let onSave: (Persistence.Category) -> Void
    let onCancel: () -> Void
    private let isNew: Bool

    init(original: Persistence.Category,
         onSave: @escaping (Persistence.Category) -> Void,
         onCancel: @escaping () -> Void) {
        _name = State(initialValue: original.name)
        _savePath = State(initialValue: original.savePath)
        _completePath = State(initialValue: original.completePath ?? "")
        _extractArchives = State(initialValue: original.extractArchives)
        _blockedExtensions = State(initialValue: original.blockedExtensions.joined(separator: ", "))
        _hasMaxRatio = State(initialValue: original.maxRatio != nil)
        _maxRatio = State(initialValue: original.maxRatio ?? 2.0)
        _hasMaxSeedTime = State(initialValue: original.maxSeedingTimeMinutes != nil)
        _maxSeedTimeMinutes = State(initialValue: original.maxSeedingTimeMinutes ?? 4320)
        self.onSave = onSave
        self.onCancel = onCancel
        self.isNew = original.name.isEmpty
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(isNew ? "New Category" : "Edit Category").font(.title3).bold().padding(.bottom, 8)
            Form {
                Section {
                    TextField("Name", text: $name).disabled(!isNew)
                    TextField("Save path", text: $savePath)
                    TextField("Complete path (optional)", text: $completePath)
                }
                Section("Post-complete") {
                    Toggle("Extract archives (.rar/.zip/.7z)", isOn: $extractArchives)
                    TextField("Blocked extensions (comma separated)", text: $blockedExtensions)
                    Text("e.g. .exe, .lnk, .scr — leading dot optional, matched case-insensitively against each file's extension. Listed files are skipped (libtorrent priority 0).")
                        .font(.caption).foregroundStyle(.secondary)
                }
                Section("Seeding limits (override global)") {
                    Toggle("Override max ratio", isOn: $hasMaxRatio)
                    if hasMaxRatio {
                        Stepper(value: $maxRatio, in: 0.0...100.0, step: 0.25) {
                            Text("Max ratio: \(maxRatio, specifier: "%.2f")")
                        }
                    }
                    Toggle("Override max seed time", isOn: $hasMaxSeedTime)
                    if hasMaxSeedTime {
                        Stepper(value: $maxSeedTimeMinutes, in: 0...1_000_000, step: 60) {
                            Text("Max seed time: \(maxSeedTimeMinutes) min")
                        }
                    }
                }
            }
            .formStyle(.grouped)
            HStack {
                Spacer()
                Button("Cancel") { onCancel() }
                Button("Save") {
                    let blocked = blockedExtensions
                        .split(separator: ",")
                        .map { $0.trimmingCharacters(in: .whitespaces) }
                        .filter { !$0.isEmpty }
                    let cat = Persistence.Category(
                        name: name,
                        savePath: savePath,
                        completePath: completePath.isEmpty ? nil : completePath,
                        extractArchives: extractArchives,
                        blockedExtensions: blocked,
                        maxRatio: hasMaxRatio ? maxRatio : nil,
                        maxSeedingTimeMinutes: hasMaxSeedTime ? maxSeedTimeMinutes : nil
                    )
                    onSave(cat)
                }
                .keyboardShortcut(.defaultAction)
                .disabled(name.isEmpty || savePath.isEmpty)
            }
            .padding(.top, 8)
        }
        .padding(20)
    }
}

// MARK: - Settings tab

/// Sidebar sections used by the native Settings screen. Keeping them in an
/// enum lets the search field filter both by section title and by keyword
/// synonyms without maintaining a parallel index.
enum SettingsSection: String, CaseIterable, Identifiable {
    case general, network, peers, connections, security, interface
    case seeding, health, vpn, disk, integrations, recovery, backup

    var id: String { rawValue }
    var title: String {
        switch self {
        case .general:      return "General"
        case .network:      return "Network"
        case .peers:        return "Peer Discovery"
        case .connections:  return "Connection Limits"
        case .security:     return "Security"
        case .interface:    return "Interface"
        case .seeding:      return "Seeding"
        case .health:       return "Health"
        case .vpn:          return "VPN"
        case .disk:         return "Disk Space"
        case .integrations: return "*arr Integrations"
        case .recovery:     return "Recovery"
        case .backup:       return "Backup"
        }
    }
    var systemImage: String {
        switch self {
        case .general:      return "gearshape"
        case .network:      return "network"
        case .peers:        return "dot.radiowaves.left.and.right"
        case .connections:  return "slider.horizontal.3"
        case .security:     return "lock.shield"
        case .interface:    return "macwindow"
        case .seeding:      return "leaf"
        case .health:       return "heart.text.square"
        case .vpn:          return "key.horizontal"
        case .disk:         return "externaldrive"
        case .integrations: return "antenna.radiowaves.left.and.right"
        case .recovery:     return "arrow.counterclockwise"
        case .backup:       return "archivebox"
        }
    }
    /// Search keywords beyond the title so typing e.g. "DHT" surfaces Peers.
    var keywords: [String] {
        switch self {
        case .general:      return ["webui","host","port","save path","listen","default"]
        case .network:      return ["diagnostics","lan","bind"]
        case .peers:        return ["dht","pex","lsd","local service","distributed hash"]
        case .connections:  return ["max","connections","upload slots","unchoke"]
        case .security:     return ["cidr","allowlist","csrf","clickjack","x-frame"]
        case .interface:    return ["menu bar","start minimized","close"]
        case .seeding:      return ["ratio","seed time","pause","remove"]
        case .health:       return ["stall","reannounce"]
        case .vpn:          return ["utun","kill switch","leak","wireguard"]
        case .disk:         return ["free space","monitor","gb"]
        case .integrations: return ["sonarr","radarr","arr","re-search"]
        case .recovery:     return ["rules","auto"]
        case .backup:       return ["export","import","restore"]
        }
    }
    func matchesQuery(_ q: String) -> Bool {
        let needle = q.lowercased().trimmingCharacters(in: .whitespaces)
        if needle.isEmpty { return true }
        if title.lowercased().contains(needle) { return true }
        return keywords.contains { $0.lowercased().contains(needle) }
    }
}

struct SettingsView: View {
    @Bindable var vm: RuntimeViewModel
    @State private var draft: Persistence.Settings?
    @State private var saved: Bool = false
    @State private var section: SettingsSection = .general
    @State private var query: String = ""

    private var visibleSections: [SettingsSection] {
        SettingsSection.allCases.filter { $0.matchesQuery(query) }
    }

    var body: some View {
        let binding = Binding<Persistence.Settings>(
            get: { draft ?? vm.settings },
            set: { draft = $0 }
        )
        HSplitView {
            VStack(spacing: 0) {
                HStack(spacing: 6) {
                    Image(systemName: "magnifyingglass")
                        .foregroundStyle(.secondary).font(.caption)
                    TextField("Search settings", text: $query)
                        .textFieldStyle(.plain)
                        .font(.caption)
                }
                .padding(8)
                Divider()
                List(selection: $section) {
                    ForEach(visibleSections) { s in
                        Label(s.title, systemImage: s.systemImage).tag(s)
                    }
                }
                .listStyle(.sidebar)
            }
            .frame(minWidth: 200, idealWidth: 220, maxWidth: 280)

            VStack(spacing: 0) {
                ScrollView {
                    VStack(alignment: .leading, spacing: 0) {
                        switch section {
                        case .general:      generalSection(binding: binding)
                        case .network:      networkSection(binding: binding)
                        case .peers:        peersSection(binding: binding)
                        case .connections:  connectionsSection(binding: binding)
                        case .security:     securitySection(binding: binding)
                        case .interface:    interfaceSection(binding: binding)
                        case .seeding:      seedingSection(binding: binding)
                        case .health:       healthSection(binding: binding)
                        case .vpn:          vpnSection(binding: binding)
                        case .disk:         diskSection(binding: binding)
                        case .integrations: integrationsSection(binding: binding)
                        case .recovery:
                            Form {
                                RecoveryRulesSection(rules: Binding(
                                    get: { (draft ?? vm.settings).recoveryRules },
                                    set: {
                                        if draft == nil { draft = vm.settings }
                                        draft?.recoveryRules = $0
                                    }
                                ))
                            }
                            .formStyle(.grouped)
                        case .backup:
                            Form { BackupRestoreSection(vm: vm) }
                                .formStyle(.grouped)
                        }
                    }
                    .padding(.bottom, 8)
                }
                Divider()
                HStack {
                    Button("Save") {
                        Task {
                            if let d = draft {
                                await vm.saveSettings(d)
                                saved = true
                            }
                        }
                    }
                    .keyboardShortcut(.defaultAction)
                    .disabled(draft == nil)
                    Button("Revert") { draft = nil; saved = false }
                        .disabled(draft == nil)
                    if saved {
                        Text("Saved").foregroundStyle(.secondary).font(.caption)
                    }
                    Spacer()
                }
                .padding(8)
            }
        }
    }

    // MARK: - General

    @ViewBuilder
    private func generalSection(binding: Binding<Persistence.Settings>) -> some View {
        Form {
            Section("WebUI") {
                TextField("Bind host", text: binding.webUIHost)
                TextField("Port", value: binding.webUIPort, format: .number)
                TextField("Username", text: binding.webUIUsername)
                SecureField("Password", text: binding.webUIPassword)
                Text("Use 0.0.0.0 for LAN clients like Sonarr, Radarr, and Overseerr on another machine. Restart Controllarr after changing the bind host or port.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Section("Listen port range") {
                TextField("Start", value: binding.listenPortRangeStart, format: .number)
                TextField("End", value: binding.listenPortRangeEnd, format: .number)
                Stepper(value: binding.stallThresholdMinutes, in: 1...240) {
                    Text("Port stall threshold: \(binding.wrappedValue.stallThresholdMinutes) min")
                }
                Button("Cycle port now") { Task { await vm.cyclePort() } }
            }
            Section("Default save path") {
                TextField("Path", text: binding.defaultSavePath)
            }
            Section("Categories") {
                Picker("When category changes", selection: binding.categoryChangeMove) {
                    Text("Ask each time").tag(CategoryMovePolicy.ask)
                    Text("Always move files").tag(CategoryMovePolicy.always)
                    Text("Never move files").tag(CategoryMovePolicy.never)
                }
                Text("Controls what happens when a torrent is reassigned to a different category. The native UI always prompts; the WebAPI uses this default when its `moveFiles` flag is omitted.")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
    }

    // MARK: - Network diagnostics

    @ViewBuilder
    private func networkSection(binding: Binding<Persistence.Settings>) -> some View {
        Form {
            Section("Network diagnostics") {
                if let diagnostics = vm.networkDiagnostics {
                    LabeledContent("Current bind", value: "\(diagnostics.bindHost):\(diagnostics.bindPort)")
                    LabeledContent("Local open URL", value: diagnostics.localOpenURL)
                    LabeledContent("Recommended LAN URL", value: diagnostics.recommendedRemoteURL ?? "—")
                    if diagnostics.lanInterfaces.isEmpty {
                        Text("No private LAN interfaces detected on this Mac.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    } else {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Detected LAN IPs")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            ForEach(diagnostics.lanInterfaces) { iface in
                                Text("\(iface.name): \(iface.ip)")
                                    .font(.caption.monospaced())
                            }
                        }
                    }
                    HStack(spacing: 8) {
                        Image(systemName: diagnostics.vpnConnected ? "lock.shield.fill" : "lock.open")
                            .foregroundStyle(diagnostics.vpnConnected ? .green : .secondary)
                        Text(
                            diagnostics.vpnConnected
                                ? "VPN: \(diagnostics.vpnInterfaceName ?? "?") (\(diagnostics.vpnInterfaceIP ?? "?"))"
                                : "VPN: not detected"
                        )
                        .font(.caption)
                        if diagnostics.vpnBoundToTorrentEngine {
                            Text("Torrent engine bound to VPN")
                                .font(.caption)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(.green.opacity(0.15), in: RoundedRectangle(cornerRadius: 4))
                        }
                    }
                    if let warning = diagnostics.warning {
                        Text(warning)
                            .font(.caption)
                            .foregroundStyle(.orange)
                    }
                } else {
                    Text("Collecting current network diagnostics…")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .formStyle(.grouped)
    }

    // MARK: - Peer discovery

    @ViewBuilder
    private func peersSection(binding: Binding<Persistence.Settings>) -> some View {
        Form {
            Section("Peer discovery") {
                Toggle("DHT (Distributed Hash Table)", isOn: binding.peerDiscovery.dhtEnabled)
                Text("Trackerless peer discovery via the BitTorrent DHT. Disable if your tracker forbids it or your VPN policy requires it.")
                    .font(.caption).foregroundStyle(.secondary)
                Toggle("PeX (Peer Exchange)", isOn: binding.peerDiscovery.pexEnabled)
                Text("Learns new peers from already-connected peers. Applies on the next Controllarr restart — libtorrent 2.x has no runtime toggle for PeX.")
                    .font(.caption).foregroundStyle(.secondary)
                Toggle("LSD (Local Service Discovery)", isOn: binding.peerDiscovery.lsdEnabled)
                Text("Broadcasts on the LAN to find other local clients. Usually noise unless you have multiple peers on the same network.")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
    }

    // MARK: - Connection limits

    @ViewBuilder
    private func connectionsSection(binding: Binding<Persistence.Settings>) -> some View {
        Form {
            Section("Connection limits") {
                optionalIntRow(
                    title: "Global max connections",
                    binding: binding.connectionLimits.globalMaxConnections,
                    defaultValue: 500
                )
                optionalIntRow(
                    title: "Per-torrent max connections",
                    binding: binding.connectionLimits.maxConnectionsPerTorrent,
                    defaultValue: 100
                )
                optionalIntRow(
                    title: "Global max uploads (unchoke slots)",
                    binding: binding.connectionLimits.globalMaxUploads,
                    defaultValue: 20
                )
                optionalIntRow(
                    title: "Per-torrent max uploads",
                    binding: binding.connectionLimits.maxUploadsPerTorrent,
                    defaultValue: 4
                )
                Text("Leave unchecked to inherit libtorrent's defaults. Raising these aggressively can saturate home routers and crowd out other traffic.")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
    }

    // MARK: - Security

    @ViewBuilder
    private func securitySection(binding: Binding<Persistence.Settings>) -> some View {
        Form {
            Section("WebUI protection") {
                Toggle("Clickjacking protection (X-Frame-Options + CSP frame-ancestors)",
                       isOn: binding.webUISecurity.clickjackingProtection)
                Toggle("CSRF protection on /api/controllarr/*",
                       isOn: binding.webUISecurity.csrfProtection)
                Text("Enable CSRF only after your WebUI client has been updated to send the X-CSRF-Token header. Other *arr tools using the qBittorrent /api/v2 surface are unaffected.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Section("IP allowlist") {
                Toggle("Restrict WebUI to specific IPs / CIDR ranges",
                       isOn: binding.webUISecurity.allowlistEnabled)
                if binding.wrappedValue.webUISecurity.allowlistEnabled {
                    ForEach(binding.wrappedValue.webUISecurity.allowedCIDRs.indices, id: \.self) { i in
                        HStack {
                            TextField("e.g. 192.168.1.0/24", text: Binding(
                                get: {
                                    let arr = binding.wrappedValue.webUISecurity.allowedCIDRs
                                    return i < arr.count ? arr[i] : ""
                                },
                                set: {
                                    var arr = binding.wrappedValue.webUISecurity.allowedCIDRs
                                    if i < arr.count { arr[i] = $0; binding.wrappedValue.webUISecurity.allowedCIDRs = arr }
                                }
                            ))
                            Button(role: .destructive) {
                                var arr = binding.wrappedValue.webUISecurity.allowedCIDRs
                                if i < arr.count {
                                    arr.remove(at: i)
                                    binding.wrappedValue.webUISecurity.allowedCIDRs = arr
                                }
                            } label: { Image(systemName: "minus.circle") }
                            .buttonStyle(.borderless)
                        }
                    }
                    Button {
                        var arr = binding.wrappedValue.webUISecurity.allowedCIDRs
                        arr.append("")
                        binding.wrappedValue.webUISecurity.allowedCIDRs = arr
                    } label: { Label("Add range", systemImage: "plus") }
                    Text("Loopback (127.0.0.1, ::1) is always allowed. Behind a reverse proxy, the X-Forwarded-For header is respected.")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
        }
        .formStyle(.grouped)
    }

    // MARK: - Interface / menu bar

    @ViewBuilder
    private func interfaceSection(binding: Binding<Persistence.Settings>) -> some View {
        Form {
            Section("Menu bar") {
                Toggle("Show Controllarr in the menu bar", isOn: binding.uiPreferences.menuBarEnabled)
                Toggle("Close window minimizes to menu bar",
                       isOn: binding.uiPreferences.closeToMenuBar)
                    .disabled(!binding.wrappedValue.uiPreferences.menuBarEnabled)
                Text("When enabled, closing the main window keeps Controllarr running in the background with only the menu-bar icon visible. Torrents continue downloading. Quit from the menu-bar menu.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Section("Launch") {
                Toggle("Start minimized to menu bar",
                       isOn: binding.uiPreferences.startMinimized)
                    .disabled(!binding.wrappedValue.uiPreferences.menuBarEnabled)
                Text("Launches Controllarr without showing the main window. Requires the menu-bar icon to be enabled.")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
    }

    // MARK: - Seeding

    @ViewBuilder
    private func seedingSection(binding: Binding<Persistence.Settings>) -> some View {
        Form {
            Section("Seeding policy") {
                Picker("When limit reached", selection: binding.seedLimitAction) {
                    Text("Pause").tag(SeedLimitAction.pause)
                    Text("Remove (keep files)").tag(SeedLimitAction.removeKeepFiles)
                    Text("Remove (delete files)").tag(SeedLimitAction.removeDeleteFiles)
                }
                optionalDoubleRow(title: "Global max ratio", binding: binding.globalMaxRatio, defaultValue: 2.0)
                optionalIntRow(title: "Global max seed time (min)", binding: binding.globalMaxSeedingTimeMinutes, defaultValue: 4320)
                Stepper(value: binding.minimumSeedTimeMinutes, in: 0...100_000) {
                    Text("Minimum seed time: \(binding.wrappedValue.minimumSeedTimeMinutes) min")
                }
            }
        }
        .formStyle(.grouped)
    }

    // MARK: - Health

    @ViewBuilder
    private func healthSection(binding: Binding<Persistence.Settings>) -> some View {
        Form {
            Section("Health monitor") {
                Stepper(value: binding.healthStallMinutes, in: 1...1440) {
                    Text("Stall threshold: \(binding.wrappedValue.healthStallMinutes) min")
                }
                Toggle("Reannounce automatically on stall", isOn: binding.healthReannounceOnStall)
            }
        }
        .formStyle(.grouped)
    }

    // MARK: - VPN

    @ViewBuilder
    private func vpnSection(binding: Binding<Persistence.Settings>) -> some View {
        Form {
            Section("VPN protection") {
                Toggle("Enable VPN monitoring", isOn: binding.vpnEnabled)
                if binding.wrappedValue.vpnEnabled {
                    Toggle("Kill switch (pause all torrents when VPN drops)", isOn: binding.vpnKillSwitch)
                    Toggle("Bind to VPN interface (prevent traffic leaks)", isOn: binding.vpnBindInterface)
                    TextField("Interface prefix", text: binding.vpnInterfacePrefix)
                        .help("PIA/WireGuard use \"utun\". Change only if your VPN uses a different naming scheme.")
                    Stepper(value: binding.vpnMonitorIntervalSeconds, in: 1...60) {
                        Text("Check interval: \(binding.wrappedValue.vpnMonitorIntervalSeconds)s")
                    }
                    if let vpn = vm.vpnStatus {
                        HStack(spacing: 8) {
                            Image(systemName: vpn.isConnected ? "checkmark.circle.fill" : "xmark.circle.fill")
                                .foregroundStyle(vpn.isConnected ? .green : .red)
                            if vpn.isConnected {
                                Text("Connected: \(vpn.interfaceName ?? "?") (\(vpn.interfaceIP ?? "?"))")
                                    .font(.caption)
                                if vpn.boundToVPN {
                                    Text("Bound")
                                        .font(.caption)
                                        .padding(.horizontal, 6)
                                        .padding(.vertical, 2)
                                        .background(.green.opacity(0.15), in: RoundedRectangle(cornerRadius: 4))
                                }
                            } else {
                                Text("VPN not detected")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                if vpn.killSwitchEngaged {
                                    Text("Kill switch active (\(vpn.pausedHashes.count) paused)")
                                        .font(.caption)
                                        .foregroundStyle(.red)
                                }
                            }
                        }
                    }
                }
            }
        }
        .formStyle(.grouped)
    }

    // MARK: - Disk

    @ViewBuilder
    private func diskSection(binding: Binding<Persistence.Settings>) -> some View {
        Form {
            Section("Disk space monitor") {
                optionalIntRow(title: "Minimum free space (GB)", binding: binding.diskSpaceMinimumGB, defaultValue: 10)
                TextField("Monitor path (empty = default save path)", text: binding.diskSpaceMonitorPath)
                if let status = vm.diskSpaceStatus {
                    HStack {
                        let freeGB = String(format: "%.1f", Double(status.freeBytes) / 1_073_741_824)
                        Text("Free: \(freeGB) GB")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        if status.isPaused {
                            Text("⚠️ Downloads paused (\(status.pausedHashes.count) torrents)")
                                .font(.caption)
                                .foregroundStyle(.orange)
                        }
                        Spacer()
                        Button("Recheck now") {
                            Task { await vm.recheckDiskSpace() }
                        }
                        .controlSize(.small)
                    }
                }
            }
        }
        .formStyle(.grouped)
    }

    // MARK: - *arr integrations

    @ViewBuilder
    private func integrationsSection(binding: Binding<Persistence.Settings>) -> some View {
        Form {
            Section("*arr re-search integration") {
                Stepper(value: binding.arrReSearchAfterHours, in: 1...168) {
                    Text("Re-search after stall: \(binding.wrappedValue.arrReSearchAfterHours) hours")
                }
                if binding.wrappedValue.arrEndpoints.isEmpty {
                    Text("No *arr endpoints configured. Use the WebUI to add Sonarr/Radarr endpoints.")
                        .font(.caption).foregroundStyle(.secondary)
                } else {
                    ForEach(binding.wrappedValue.arrEndpoints) { ep in
                        HStack {
                            Image(systemName: ep.kind == .sonarr ? "tv" : "film")
                                .foregroundStyle(.secondary)
                            VStack(alignment: .leading) {
                                Text(ep.name).font(.callout)
                                Text(ep.baseURL).font(.caption).foregroundStyle(.secondary)
                            }
                            Spacer()
                            Text(ep.kind.rawValue.capitalized)
                                .font(.caption)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(.quaternary, in: RoundedRectangle(cornerRadius: 4))
                        }
                    }
                }
            }
        }
        .formStyle(.grouped)
    }

    @ViewBuilder
    private func optionalDoubleRow(title: String, binding: Binding<Double?>, defaultValue: Double) -> some View {
        HStack {
            Toggle(title, isOn: Binding(
                get: { binding.wrappedValue != nil },
                set: { binding.wrappedValue = $0 ? (binding.wrappedValue ?? defaultValue) : nil }
            ))
            if let v = binding.wrappedValue {
                Stepper(
                    value: Binding(get: { v }, set: { binding.wrappedValue = $0 }),
                    in: 0.0...100.0,
                    step: 0.25
                ) {
                    Text(String(format: "%.2f", v)).monospacedDigit()
                }
                .fixedSize()
            }
        }
    }

    @ViewBuilder
    private func optionalIntRow(title: String, binding: Binding<Int?>, defaultValue: Int) -> some View {
        HStack {
            Toggle(title, isOn: Binding(
                get: { binding.wrappedValue != nil },
                set: { binding.wrappedValue = $0 ? (binding.wrappedValue ?? defaultValue) : nil }
            ))
            if let v = binding.wrappedValue {
                Stepper(
                    value: Binding(get: { v }, set: { binding.wrappedValue = $0 }),
                    in: 0...1_000_000,
                    step: 60
                ) {
                    Text("\(v) min").monospacedDigit()
                }
                .fixedSize()
            }
        }
    }
}

// MARK: - Health tab

struct HealthView: View {
    @Bindable var vm: RuntimeViewModel
    var body: some View {
        VStack(spacing: 0) {
            if vm.healthIssues.isEmpty {
                VStack(spacing: 8) {
                    Image(systemName: "checkmark.seal.fill").font(.largeTitle).foregroundStyle(.green)
                    Text("All torrents healthy").foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                Table(vm.healthIssues) {
                    TableColumn("Torrent") { i in
                        Text(i.name).lineLimit(1).truncationMode(.middle)
                    }
                    TableColumn("Reason") { i in
                        Text(friendly(i.reason))
                    }.width(min: 160, ideal: 180)
                    TableColumn("Progress") { i in
                        Text(String(format: "%.0f%%", i.lastProgress * 100)).monospacedDigit()
                    }.width(min: 80, ideal: 90)
                    TableColumn("First seen") { i in
                        Text(i.firstSeen, style: .relative).font(.caption)
                    }.width(min: 110, ideal: 130)
                    TableColumn("") { i in
                        HStack(spacing: 6) {
                            Button("Recover") {
                                Task {
                                    try? await vm.runRecovery(hash: i.infoHash)
                                }
                            }
                            .buttonStyle(.borderedProminent)
                            .controlSize(.small)
                            Button("Clear") {
                                Task { await vm.clearHealthIssue(hash: i.infoHash) }
                            }
                            .controlSize(.small)
                        }
                    }.width(min: 150, ideal: 170)
                }
            }
        }
    }

    private func friendly(_ r: HealthMonitor.Reason) -> String {
        switch r {
        case .metadataTimeout:   return "Metadata timeout"
        case .noPeers:           return "No peers"
        case .stalledWithPeers:  return "Stalled (with peers)"
        case .awaitingRecheck:   return "Awaiting recheck"
        }
    }
}

// MARK: - Post-processor tab

struct PostProcessorView: View {
    @Bindable var vm: RuntimeViewModel
    var body: some View {
        if vm.postRecords.isEmpty {
            Text("No post-processing activity yet")
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            Table(vm.postRecords, columns: {
                TableColumn("Torrent") { r in
                    Text(r.name).lineLimit(1).truncationMode(.middle)
                }
                TableColumn("Category") { r in
                    Text(r.category ?? "—").foregroundStyle(.secondary)
                }.width(min: 80, ideal: 100)
                TableColumn("Stage") { r in
                    Text(stageLabel(r.stage))
                }.width(min: 120, ideal: 150)
                TableColumn("Message") { r in
                    Text(r.message ?? "").font(.caption).foregroundStyle(.secondary)
                        .lineLimit(1).truncationMode(.middle)
                }
                TableColumn("Updated") { r in
                    Text(r.lastUpdated, style: .relative).font(.caption)
                }.width(min: 100, ideal: 120)
                TableColumn("") { r in
                    if case .failed = r.stage {
                        Button("Retry") {
                            Task { try? await vm.retryPostProcessor(hash: r.infoHash) }
                        }
                        .buttonStyle(.borderedProminent)
                        .controlSize(.small)
                    }
                }.width(min: 70, ideal: 80)
            })
        }
    }

    private func stageLabel(_ stage: PostProcessor.Stage) -> String {
        switch stage {
        case .pending:                       return "pending"
        case .movingStorage(let t, _):       return "moving → \(URL(fileURLWithPath: t).lastPathComponent)"
        case .extracting:                    return "extracting"
        case .done:                          return "done"
        case .failed(let reason):            return "failed: \(reason)"
        }
    }
}

// MARK: - Seeding tab

struct SeedingView: View {
    @Bindable var vm: RuntimeViewModel
    var body: some View {
        if vm.seedingLog.isEmpty {
            Text("No seeding-policy actions yet")
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            Table(vm.seedingLog) {
                TableColumn("Torrent") { e in
                    Text(e.name).lineLimit(1).truncationMode(.middle)
                }
                TableColumn("Action") { e in
                    Text(e.action.rawValue)
                }.width(min: 140, ideal: 160)
                TableColumn("Reason") { e in
                    Text(e.reason).font(.caption).foregroundStyle(.secondary)
                }
                TableColumn("When") { e in
                    Text(e.timestamp, style: .relative).font(.caption)
                }.width(min: 100, ideal: 120)
            }
        }
    }
}

// MARK: - Log tab

struct LogView: View {
    @Bindable var vm: RuntimeViewModel
    @State private var filter: String = ""

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                TextField("Filter", text: $filter)
                    .textFieldStyle(.roundedBorder)
                    .frame(maxWidth: 240)
                Spacer()
            }
            .padding(8)
            Divider()
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 2) {
                    ForEach(filtered) { entry in
                        HStack(alignment: .top, spacing: 8) {
                            Text(entry.timestamp, format: .dateTime.hour().minute().second())
                                .font(.caption.monospacedDigit())
                                .foregroundStyle(.secondary)
                                .frame(width: 70, alignment: .leading)
                            Text(entry.level.rawValue.uppercased())
                                .font(.caption2.monospacedDigit())
                                .foregroundStyle(levelColor(entry.level))
                                .frame(width: 44, alignment: .leading)
                            Text("[\(entry.source)]")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .frame(width: 120, alignment: .leading)
                                .lineLimit(1)
                            Text(entry.message)
                                .font(.caption)
                                .textSelection(.enabled)
                            Spacer(minLength: 0)
                        }
                        .padding(.horizontal, 8)
                    }
                }
                .padding(.vertical, 6)
            }
        }
    }

    private var filtered: [Logger.Entry] {
        guard !filter.isEmpty else { return vm.logEntries.reversed() }
        let lower = filter.lowercased()
        return vm.logEntries.reversed().filter {
            $0.message.lowercased().contains(lower) || $0.source.lowercased().contains(lower)
        }
    }

    private func levelColor(_ l: Logger.Level) -> Color {
        switch l {
        case .debug: return .secondary
        case .info:  return .blue
        case .warn:  return .orange
        case .error: return .red
        }
    }
}

// MARK: - Recovery tab

struct RecoveryView: View {
    @Bindable var vm: RuntimeViewModel
    var body: some View {
        if vm.recoveryRecords.isEmpty {
            VStack(spacing: 8) {
                Image(systemName: "arrow.counterclockwise").font(.largeTitle).foregroundStyle(.secondary)
                Text("No recovery actions yet").foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            Table(vm.recoveryRecords) {
                TableColumn("Torrent") { r in
                    Text(r.name).lineLimit(1).truncationMode(.middle)
                }
                TableColumn("Reason") { r in
                    Text(triggerLabel(r.reason)).font(.caption)
                }.width(min: 120, ideal: 140)
                TableColumn("Action") { r in
                    Text(actionLabel(r.action)).font(.caption)
                }.width(min: 100, ideal: 120)
                TableColumn("Source") { r in
                    Text(r.source.rawValue)
                        .font(.caption)
                        .foregroundStyle(r.source == .manual ? .blue : .secondary)
                }.width(min: 70, ideal: 80)
                TableColumn("Result") { r in
                    HStack(spacing: 4) {
                        Image(systemName: r.success ? "checkmark.circle.fill" : "xmark.circle.fill")
                            .font(.caption)
                            .foregroundStyle(r.success ? .green : .red)
                        Text(r.message).font(.caption).foregroundStyle(.secondary)
                            .lineLimit(1).truncationMode(.tail)
                    }
                }.width(min: 180, ideal: 220)
                TableColumn("When") { r in
                    Text(r.timestamp, style: .relative).font(.caption)
                }.width(min: 100, ideal: 120)
            }
        }
    }

    private func triggerLabel(_ t: RecoveryTrigger) -> String {
        switch t {
        case .metadataTimeout:              return "Metadata timeout"
        case .noPeers:                      return "No peers"
        case .stalledWithPeers:             return "Stalled (peers)"
        case .awaitingRecheck:              return "Awaiting recheck"
        case .postProcessMoveFailed:        return "PP move failed"
        case .postProcessExtractionFailed:  return "PP extraction failed"
        case .diskPressure:                 return "Disk pressure"
        }
    }

    private func actionLabel(_ a: RecoveryAction) -> String {
        switch a {
        case .reannounce:         return "Reannounce"
        case .pause:              return "Pause"
        case .removeKeepFiles:    return "Remove (keep)"
        case .removeDeleteFiles:  return "Remove (delete)"
        case .retryPostProcess:   return "Retry PP"
        }
    }
}

// MARK: - *arr Activity tab

struct ArrView: View {
    @Bindable var vm: RuntimeViewModel
    var body: some View {
        if vm.arrNotifications.isEmpty {
            VStack(spacing: 8) {
                Image(systemName: "antenna.radiowaves.left.and.right").font(.largeTitle).foregroundStyle(.secondary)
                Text("No *arr re-search activity yet").foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            Table(vm.arrNotifications) {
                TableColumn("Torrent") { n in
                    Text(n.name).lineLimit(1).truncationMode(.middle)
                }
                TableColumn("Endpoint") { n in
                    Text(n.endpoint).font(.caption)
                }.width(min: 100, ideal: 120)
                TableColumn("Result") { n in
                    HStack(spacing: 4) {
                        Image(systemName: n.success ? "checkmark.circle.fill" : "xmark.circle.fill")
                            .font(.caption)
                            .foregroundStyle(n.success ? .green : .red)
                        Text(n.message).font(.caption).foregroundStyle(.secondary)
                            .lineLimit(1).truncationMode(.tail)
                    }
                }.width(min: 200, ideal: 260)
                TableColumn("When") { n in
                    Text(n.timestamp, style: .relative).font(.caption)
                }.width(min: 100, ideal: 120)
            }
        }
    }
}

// MARK: - Recovery rules editor (in Settings)

private struct RecoveryRulesSection: View {
    @Binding var rules: [RecoveryRule]

    var body: some View {
        Section("Recovery rules") {
            if rules.isEmpty {
                Text("No recovery rules configured. Add a rule to automatically react to unhealthy torrents.")
                    .font(.caption).foregroundStyle(.secondary)
            } else {
                ForEach(Array(rules.enumerated()), id: \.offset) { idx, rule in
                    HStack(spacing: 8) {
                        Toggle("", isOn: Binding(
                            get: { rules[idx].enabled },
                            set: { rules[idx].enabled = $0 }
                        ))
                        .labelsHidden()
                        .toggleStyle(.checkbox)

                        Picker("Trigger", selection: Binding(
                            get: { rules[idx].trigger },
                            set: { rules[idx].trigger = $0 }
                        )) {
                            ForEach(RecoveryTrigger.allCases, id: \.rawValue) { t in
                                Text(friendlyTrigger(t)).tag(t)
                            }
                        }
                        .frame(maxWidth: 180)

                        Image(systemName: "arrow.right")
                            .font(.caption)
                            .foregroundStyle(.secondary)

                        Picker("Action", selection: Binding(
                            get: { rules[idx].action },
                            set: { rules[idx].action = $0 }
                        )) {
                            ForEach(RecoveryAction.allCases, id: \.rawValue) { a in
                                Text(friendlyAction(a)).tag(a)
                            }
                        }
                        .frame(maxWidth: 160)

                        Stepper(value: Binding(
                            get: { rules[idx].delayMinutes },
                            set: { rules[idx].delayMinutes = $0 }
                        ), in: 0...1440, step: 5) {
                            Text("after \(rules[idx].delayMinutes) min").font(.caption).monospacedDigit()
                        }
                        .frame(maxWidth: 170)

                        Button(role: .destructive) {
                            rules.remove(at: idx)
                        } label: {
                            Image(systemName: "trash")
                                .font(.caption)
                        }
                        .buttonStyle(.borderless)
                    }
                }
            }
            Button {
                rules.append(RecoveryRule(
                    enabled: true,
                    trigger: .stalledWithPeers,
                    action: .reannounce,
                    delayMinutes: 30
                ))
            } label: {
                Label("Add Rule", systemImage: "plus")
            }
        }
    }

    private func friendlyTrigger(_ t: RecoveryTrigger) -> String {
        switch t {
        case .metadataTimeout:              return "Metadata timeout"
        case .noPeers:                      return "No peers"
        case .stalledWithPeers:             return "Stalled (with peers)"
        case .awaitingRecheck:              return "Awaiting recheck"
        case .postProcessMoveFailed:        return "Post-process move failed"
        case .postProcessExtractionFailed:  return "Post-process extraction failed"
        case .diskPressure:                 return "Disk pressure"
        }
    }

    private func friendlyAction(_ a: RecoveryAction) -> String {
        switch a {
        case .reannounce:         return "Reannounce"
        case .pause:              return "Pause"
        case .removeKeepFiles:    return "Remove (keep files)"
        case .removeDeleteFiles:  return "Remove (delete files)"
        case .retryPostProcess:   return "Retry post-process"
        }
    }
}

// MARK: - Backup & Restore (in Settings)

private struct BackupRestoreSection: View {
    @Bindable var vm: RuntimeViewModel
    @State private var includeSecrets = false
    @State private var backupMessage: String?
    @State private var importMessage: String?

    var body: some View {
        Section("Backup & Restore") {
            HStack {
                Toggle("Include secrets (passwords, API keys)", isOn: $includeSecrets)
                Spacer()
                Button("Export Backup") {
                    Task { await exportBackup() }
                }
            }
            if let msg = backupMessage {
                Text(msg).font(.caption).foregroundStyle(.secondary)
            }
            HStack {
                Button("Import Backup") {
                    importBackup()
                }
                if let msg = importMessage {
                    Text(msg).font(.caption).foregroundStyle(msg.contains("Error") ? .red : .secondary)
                }
            }
        }
    }

    private func exportBackup() async {
        guard let data = await vm.exportBackup(includeSecrets: includeSecrets) else {
            backupMessage = "Failed to create backup."
            return
        }
        let panel = NSSavePanel()
        let timestamp = ISO8601DateFormatter().string(from: Date())
            .replacingOccurrences(of: ":", with: "-")
        panel.nameFieldStringValue = "controllarr-backup-\(timestamp).json"
        panel.allowedContentTypes = [.json]
        let response = panel.runModal()
        if response == .OK, let url = panel.url {
            do {
                try data.write(to: url)
                backupMessage = "Backup exported to \(url.lastPathComponent)."
            } catch {
                backupMessage = "Error writing backup: \(error.localizedDescription)"
            }
        }
    }

    private func importBackup() {
        let panel = NSOpenPanel()
        panel.title = "Select Controllarr backup"
        panel.allowedContentTypes = [.json]
        panel.allowsMultipleSelection = false
        panel.begin { response in
            guard response == .OK, let url = panel.urls.first else { return }
            Task {
                do {
                    let data = try Data(contentsOf: url)
                    try await vm.importBackup(data: data)
                    importMessage = "Backup restored from \(url.lastPathComponent)."
                } catch {
                    importMessage = "Error: \(error.localizedDescription)"
                }
            }
        }
    }
}

// MARK: - Formatting helpers

func formatRate(_ bps: Int64) -> String {
    let kb = Double(bps) / 1024
    if kb < 1024 { return String(format: "%.0f KiB/s", kb) }
    return String(format: "%.1f MiB/s", kb / 1024)
}

func formatBytes(_ bytes: Int64) -> String {
    let formatter = ByteCountFormatter()
    formatter.countStyle = .binary
    return formatter.string(fromByteCount: bytes)
}
