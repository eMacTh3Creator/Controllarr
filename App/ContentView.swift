//
//  ContentView.swift
//  Controllarr — Phase 2
//
//  Native main window. NavigationSplitView with sidebar tabs for
//  Torrents, Categories, Settings, Health, Post-Processing, Seeding and
//  the log viewer. All tabs bind to the shared RuntimeViewModel.
//

import SwiftUI
import TorrentEngine
import Persistence
import Services

enum Tab: String, CaseIterable, Identifiable {
    case torrents, categories, settings, health, postProcessor, seeding, log
    var id: String { rawValue }

    var title: String {
        switch self {
        case .torrents:      return "Torrents"
        case .categories:    return "Categories"
        case .settings:      return "Settings"
        case .health:        return "Health"
        case .postProcessor: return "Post-Processor"
        case .seeding:       return "Seeding"
        case .log:           return "Log"
        }
    }

    var systemImage: String {
        switch self {
        case .torrents:      return "arrow.up.arrow.down"
        case .categories:    return "folder"
        case .settings:      return "gearshape"
        case .health:        return "heart.text.square"
        case .postProcessor: return "shippingbox"
        case .seeding:       return "leaf"
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
                    case .postProcessor: PostProcessorView(vm: vm)
                    case .seeding:       SeedingView(vm: vm)
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
        HStack(spacing: 12) {
            Image(systemName: "circle.fill")
                .font(.system(size: 8))
                .foregroundStyle(vm.session.hasIncomingConnections ? .green : .orange)
            Text("Port \(vm.session.listenPort)")
                .font(.callout.monospacedDigit())
            Text("\(vm.session.numTorrents) torrents")
                .font(.callout.monospacedDigit())
                .foregroundStyle(.secondary)
            Text("↓ \(formatRate(vm.session.downloadRate))")
                .font(.callout.monospacedDigit())
                .foregroundStyle(.blue)
            Text("↑ \(formatRate(vm.session.uploadRate))")
                .font(.callout.monospacedDigit())
                .foregroundStyle(.green)
            if let vpn = vm.vpnStatus, vm.settings.vpnEnabled {
                HStack(spacing: 4) {
                    Image(systemName: vpn.isConnected ? "lock.shield.fill" : "lock.shield")
                        .font(.caption)
                    Text(vpn.isConnected
                         ? "VPN \(vpn.interfaceName ?? "")"
                         : "VPN down")
                        .font(.caption)
                }
                .foregroundStyle(vpn.isConnected ? .green : .red)
            }
            if let ds = vm.diskSpaceStatus, ds.isPaused {
                HStack(spacing: 4) {
                    Image(systemName: "externaldrive.badge.exclamationmark")
                        .font(.caption)
                    Text("Low disk")
                        .font(.caption)
                }
                .foregroundStyle(.orange)
            }
        }
    }
}

// MARK: - Torrents tab

struct TorrentsView: View {
    @Bindable var vm: RuntimeViewModel
    @State private var addOpen = false
    @State private var magnetURI = ""
    @State private var addCategory: String = ""
    @State private var addError: String?
    @State private var selectedHash: String?

    var body: some View {
        VSplitView {
            VStack(spacing: 0) {
                Table(vm.torrents, selection: $selectedHash) {
                    TableColumn("Name") { t in
                        Text(t.name).lineLimit(1).truncationMode(.middle)
                    }
                    TableColumn("Size") { t in
                        Text(formatBytes(t.totalWanted)).monospacedDigit()
                    }.width(min: 80, ideal: 90)
                    TableColumn("Progress") { t in
                        VStack(alignment: .leading, spacing: 2) {
                            ProgressView(value: Double(t.progress))
                                .progressViewStyle(.linear)
                                .frame(width: 110)
                            Text(String(format: "%.0f%%", t.progress * 100))
                                .font(.caption.monospacedDigit())
                                .foregroundStyle(.secondary)
                        }
                    }.width(min: 120, ideal: 140)
                    TableColumn("State") { t in
                        Text(t.paused ? "paused" : "\(t.state)")
                            .font(.caption)
                            .foregroundStyle(t.paused ? .orange : .primary)
                    }.width(min: 70, ideal: 90)
                    TableColumn("↓") { t in
                        Text(formatRate(t.downloadRate)).monospacedDigit().font(.caption)
                    }.width(min: 70, ideal: 80)
                    TableColumn("↑") { t in
                        Text(formatRate(t.uploadRate)).monospacedDigit().font(.caption)
                    }.width(min: 70, ideal: 80)
                    TableColumn("Peers") { t in
                        Text("\(t.numPeers)").monospacedDigit().font(.caption)
                    }.width(min: 50, ideal: 60)
                    TableColumn("Ratio") { t in
                        Text(String(format: "%.2f", t.ratio)).monospacedDigit().font(.caption)
                    }.width(min: 55, ideal: 65)
                    TableColumn("Category") { t in
                        Text(t.category ?? "—").font(.caption).foregroundStyle(.secondary)
                    }.width(min: 80, ideal: 100)
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
        .sheet(isPresented: $addOpen) {
            addMagnetSheet
                .frame(minWidth: 460, minHeight: 220)
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
                CategoryDetail(category: cat)
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
                    await vm.saveCategory(updated)
                    editing = nil
                }
            } onCancel: {
                editing = nil
            }
            .frame(minWidth: 520, minHeight: 460)
        }
    }
}

private struct CategoryDetail: View {
    let category: Persistence.Category
    var body: some View {
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
        .padding()
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

struct SettingsView: View {
    @Bindable var vm: RuntimeViewModel
    @State private var draft: Persistence.Settings?
    @State private var saved: Bool = false

    var body: some View {
        let binding = Binding<Persistence.Settings>(
            get: { draft ?? vm.settings },
            set: { draft = $0 }
        )
        Form {
            Section("WebUI") {
                TextField("Host", text: binding.webUIHost)
                TextField("Port", value: binding.webUIPort, format: .number)
                TextField("Username", text: binding.webUIUsername)
                SecureField("Password", text: binding.webUIPassword)
            }
            Section("Listen port range") {
                TextField("Start", value: binding.listenPortRangeStart, format: .number)
                TextField("End", value: binding.listenPortRangeEnd, format: .number)
                Stepper(value: binding.stallThresholdMinutes, in: 1...240) {
                    Text("Port stall threshold: \(binding.wrappedValue.stallThresholdMinutes) min")
                }
                Button("Cycle port now") {
                    Task { await vm.cyclePort() }
                }
            }
            Section("Default save path") {
                TextField("Path", text: binding.defaultSavePath)
            }
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
            Section("Health monitor") {
                Stepper(value: binding.healthStallMinutes, in: 1...1440) {
                    Text("Stall threshold: \(binding.wrappedValue.healthStallMinutes) min")
                }
                Toggle("Reannounce automatically on stall", isOn: binding.healthReannounceOnStall)
            }
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
                    }
                }
            }
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
            Section {
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
                    Button("Revert") { draft = nil; saved = false }
                    if saved {
                        Text("Saved").foregroundStyle(.secondary).font(.caption)
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
                        Button("Clear") {
                            Task { await vm.clearHealthIssue(hash: i.infoHash) }
                        }
                    }.width(min: 70, ideal: 80)
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
