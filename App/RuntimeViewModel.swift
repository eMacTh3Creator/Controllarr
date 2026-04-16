//
//  RuntimeViewModel.swift
//  Controllarr — Phase 2
//
//  Main-actor observable that the SwiftUI window reads from. Owns the
//  ControllarrRuntime and a 2s polling task that mirrors the runtime's
//  own tick cadence, pulling snapshots out of each actor and republishing
//  them for the UI.
//
//  The AppDelegate used to hold the runtime directly; ownership moved
//  here so SwiftUI views have a single source of truth and the menu-bar
//  accessory can read the same published state.
//

import SwiftUI
import Observation
import ControllarrCore
import TorrentEngine
import Persistence
import PortWatcher
import Services

@MainActor
@Observable
final class RuntimeViewModel {

    /// Shared instance so AppDelegate (status menu) and the SwiftUI
    /// window can both talk to the same runtime without threading an
    /// environment value through NSApplicationDelegateAdaptor.
    static let shared = RuntimeViewModel()

    // MARK: - Published state

    var isBooting: Bool = true
    var bootError: String?
    var torrents: [TorrentStats] = []
    var session: SessionStats = .zero
    var categories: [Persistence.Category] = []
    var settings: Persistence.Settings = .defaults(homeDir: FileManager.default.homeDirectoryForCurrentUser)
    var healthIssues: [HealthMonitor.Issue] = []
    var postRecords: [PostProcessor.Record] = []
    var seedingLog: [SeedingPolicy.Enforcement] = []
    var logEntries: [Logger.Entry] = []
    var diskSpaceStatus: DiskSpaceMonitor.Status?
    var vpnStatus: VPNMonitor.Status?
    var networkDiagnostics: NetworkDiagnostics.Snapshot?
    var arrNotifications: [ArrNotifier.Notification] = []
    var recoveryRecords: [RecoveryCenter.Record] = []

    // MARK: - Runtime

    private(set) var runtime: ControllarrRuntime?
    private var pollTask: Task<Void, Never>?

    private init() {}

    func boot() async {
        guard runtime == nil else { return }
        let webUIRoot = Bundle.main.url(forResource: "dist", withExtension: nil)
        let rt = await ControllarrRuntime(webUIRoot: webUIRoot)
        self.runtime = rt
        do {
            try await rt.start()
            isBooting = false
            startPolling()
            // Drain any .torrent files or magnet: links that arrived
            // while the runtime was still booting.
            if let delegate = NSApp.delegate as? AppDelegate {
                delegate.drainPendingOpens()
            }
        } catch {
            bootError = "\(error)"
            isBooting = false
        }
    }

    func shutdown() async {
        pollTask?.cancel()
        pollTask = nil
        await runtime?.shutdown()
    }

    private func startPolling() {
        pollTask?.cancel()
        pollTask = Task { [weak self] in
            while !Task.isCancelled {
                await self?.refresh()
                try? await Task.sleep(nanoseconds: 2_000_000_000)
            }
        }
    }

    func refresh() async {
        guard let runtime else { return }
        let engine = runtime.engine
        let store = runtime.store
        let pp = runtime.postProcessor
        let sp = runtime.seedingPolicy
        let hm = runtime.healthMonitor
        let logger = runtime.logger
        let dsm = runtime.diskSpaceMonitor
        let vpn = runtime.vpnMonitor
        let an = runtime.arrNotifier
        let rc = runtime.recoveryCenter

        async let t = engine.pollStats()
        async let s = engine.sessionStats()
        async let c = store.categories()
        async let st = store.settings()
        async let h = hm.snapshot()
        async let p = pp.snapshot()
        async let sl = sp.snapshot()
        async let ds = dsm.snapshot()
        async let vp = vpn.snapshot()
        async let ar = an.snapshot()
        async let rr = rc.snapshot()
        let log = await logger.snapshot(limit: 200)

        let torrents = await t
        let session = await s
        let categories = await c
        let settings = await st
        let health = await h
        let post = await p
        let seeding = await sl
        let disk = await ds
        let vpnStatus = await vp
        let arr = await ar
        let recovery = await rr

        self.torrents = torrents
        self.session = session
        self.categories = categories
        self.settings = settings
        self.healthIssues = health
        self.postRecords = post
        self.seedingLog = seeding
        self.diskSpaceStatus = disk
        self.vpnStatus = vpnStatus
        self.networkDiagnostics = NetworkDiagnostics.snapshot(
            bindHost: settings.webUIHost,
            bindPort: settings.webUIPort,
            vpnStatus: vpnStatus
        )
        self.arrNotifications = arr
        self.recoveryRecords = recovery
        self.logEntries = log
    }

    // MARK: - Actions

    func addMagnet(_ uri: String, category: String?) async throws {
        guard let runtime else { return }
        _ = try await runtime.engine.addMagnet(uri, category: category)
        await refresh()
    }

    func addTorrentFile(at url: URL, category: String?) async throws {
        guard let runtime else { return }
        _ = try await runtime.engine.addTorrentFile(at: url, category: category)
        await refresh()
    }

    func pause(hash: String) async {
        guard let runtime else { return }
        _ = await runtime.engine.pause(infoHash: hash)
        await refresh()
    }

    func resume(hash: String) async {
        guard let runtime else { return }
        _ = await runtime.engine.resume(infoHash: hash)
        await refresh()
    }

    func remove(hash: String, deleteFiles: Bool) async {
        guard let runtime else { return }
        _ = await runtime.engine.remove(infoHash: hash, deleteFiles: deleteFiles)
        await refresh()
    }

    func reannounce(hash: String) async {
        guard let runtime else { return }
        _ = await runtime.engine.reannounce(infoHash: hash)
    }

    func cyclePort() async {
        guard let runtime else { return }
        await runtime.portWatcher.forceCycle(reason: "native UI")
    }

    func saveCategory(_ category: Persistence.Category) async {
        guard let runtime else { return }
        await runtime.store.upsertCategory(category)
        await runtime.engine.registerBlockedExtensions(category.blockedExtensions, forCategory: category.name)
        await refresh()
    }

    func deleteCategory(named name: String) async {
        guard let runtime else { return }
        await runtime.store.removeCategory(named: name)
        await refresh()
    }

    func saveSettings(_ newSettings: Persistence.Settings) async {
        guard let runtime else { return }
        await runtime.store.replaceSettings(newSettings)
        await refresh()
    }

    func clearHealthIssue(hash: String) async {
        guard let runtime else { return }
        await runtime.healthMonitor.clearIssue(hash: hash)
        await refresh()
    }

    func runRecovery(hash: String, action: RecoveryAction? = nil) async throws {
        guard let runtime else { return }
        _ = try await runtime.recoveryCenter.runRecovery(for: hash, action: action)
        await refresh()
    }

    func retryPostProcessor(hash: String) async throws {
        guard let runtime else { return }
        _ = try await runtime.postProcessor.retry(infoHash: hash)
        await refresh()
    }

    func recheckDiskSpace() async {
        guard let runtime else { return }
        await runtime.diskSpaceMonitor.forceEvaluate()
        await refresh()
    }

    func exportBackup(includeSecrets: Bool) async -> Data? {
        guard let runtime else { return nil }
        let archive = await runtime.store.exportBackup(includeSecrets: includeSecrets)
        return try? JSONEncoder().encode(archive)
    }

    func importBackup(data: Data) async throws {
        guard let runtime else { return }
        let archive = try JSONDecoder().decode(BackupArchive.self, from: data)
        _ = try await runtime.store.restoreBackup(archive)
        await refresh()
    }

    func openWebUI() {
        let host = NetworkDiagnostics.localHostForOpen(
            NetworkDiagnostics.normalizedHost(settings.webUIHost)
        )
        let url = URL(string: "http://\(host):\(settings.webUIPort)/")
        if let url { NSWorkspace.shared.open(url) }
    }

    // MARK: - Per-torrent detail

    func fileInfo(for hash: String) async -> [FileInfo] {
        guard let runtime else { return [] }
        return await runtime.engine.fileInfo(for: hash) ?? []
    }

    func setFilePriorities(_ priorities: [Int], for hash: String) async -> Bool {
        guard let runtime else { return false }
        return await runtime.engine.setFilePriorities(priorities, for: hash)
    }

    func trackers(for hash: String) async -> [TrackerInfo] {
        guard let runtime else { return [] }
        return await runtime.engine.trackers(for: hash) ?? []
    }

    func peers(for hash: String) async -> [PeerInfo] {
        guard let runtime else { return [] }
        return await runtime.engine.peers(for: hash) ?? []
    }
}

extension SessionStats {
    static var zero: SessionStats {
        SessionStats(
            downloadRate: 0,
            uploadRate: 0,
            totalDownloaded: 0,
            totalUploaded: 0,
            numTorrents: 0,
            numPeersConnected: 0,
            hasIncomingConnections: false,
            listenPort: 0
        )
    }
}
