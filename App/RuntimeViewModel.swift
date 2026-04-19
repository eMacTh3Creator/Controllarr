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

import AppKit
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

    /// Present when a duplicate add-request came in and the active
    /// `DuplicateTorrentPolicy` is `.ask`. The view layer reads this to
    /// surface the prompt sheet; resolving the prompt (merge / ignore)
    /// clears it.
    struct PendingDuplicate: Identifiable {
        let id = UUID()
        let infoHash: String
        let source: Source
        let incomingTrackers: [String]
        enum Source {
            case magnet(uri: String, category: String?)
            case torrentFile(url: URL, category: String?)
        }
    }
    var pendingDuplicate: PendingDuplicate?

    // MARK: - Runtime

    private(set) var runtime: ControllarrRuntime?
    private var fastPollTask: Task<Void, Never>?
    private var slowPollTask: Task<Void, Never>?
    private var isRefreshingFast = false
    private var isRefreshingSlow = false

    private let fastRefreshInterval: UInt64 = 2_000_000_000
    private let slowRefreshInterval: UInt64 = 10_000_000_000

    private init() {}

    func boot() async {
        guard runtime == nil else { return }
        let webUIRoot = Bundle.main.url(forResource: "dist", withExtension: nil)
        let rt = await ControllarrRuntime(webUIRoot: webUIRoot)
        self.runtime = rt
        do {
            try await rt.start()
            await refreshAll()
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
        fastPollTask?.cancel()
        slowPollTask?.cancel()
        fastPollTask = nil
        slowPollTask = nil
        await runtime?.shutdown()
    }

    private func startPolling() {
        fastPollTask?.cancel()
        slowPollTask?.cancel()
        let fastInterval = fastRefreshInterval
        let slowInterval = slowRefreshInterval

        fastPollTask = Task { [weak self] in
            while !Task.isCancelled {
                await self?.refreshFast()
                try? await Task.sleep(nanoseconds: fastInterval)
            }
        }

        slowPollTask = Task { [weak self] in
            while !Task.isCancelled {
                await self?.refreshSlow()
                try? await Task.sleep(nanoseconds: slowInterval)
            }
        }
    }

    func refresh() async {
        await refreshAll()
    }

    func refreshAll() async {
        await refreshFast()
        await refreshSlow()
    }

    func refreshFast() async {
        guard let runtime, !isRefreshingFast else { return }
        isRefreshingFast = true
        defer { isRefreshingFast = false }

        let engine = runtime.engine
        let pp = runtime.postProcessor
        let hm = runtime.healthMonitor
        let dsm = runtime.diskSpaceMonitor
        let vpn = runtime.vpnMonitor

        async let t = engine.pollStats()
        async let s = engine.sessionStats()
        async let h = hm.snapshot()
        async let p = pp.snapshot()
        async let ds = dsm.snapshot()
        async let vp = vpn.snapshot()

        let torrents = await t
        let session = await s
        let health = await h
        let post = await p
        let disk = await ds
        let vpnStatus = await vp

        self.torrents = torrents
        self.session = session
        self.healthIssues = health
        self.postRecords = post
        self.diskSpaceStatus = disk
        self.vpnStatus = vpnStatus
        self.networkDiagnostics = NetworkDiagnostics.snapshot(
            bindHost: settings.webUIHost,
            bindPort: settings.webUIPort,
            vpnStatus: vpnStatus
        )
    }

    func refreshSlow() async {
        guard let runtime, !isRefreshingSlow else { return }
        isRefreshingSlow = true
        defer { isRefreshingSlow = false }

        let store = runtime.store
        let sp = runtime.seedingPolicy
        let logger = runtime.logger
        let an = runtime.arrNotifier
        let rc = runtime.recoveryCenter

        async let c = store.categories()
        async let st = store.settings()
        async let sl = sp.snapshot()
        async let ar = an.snapshot()
        async let rr = rc.snapshot()
        let log = await logger.snapshot(limit: 200)

        let categories = await c
        let settings = await st
        let seeding = await sl
        let arr = await ar
        let recovery = await rr

        self.categories = categories
        self.settings = settings
        self.seedingLog = seeding
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

    /// Add a magnet using the active duplicate-policy. `interactive` should
    /// be true for any path driven by the native UI — in that mode a
    /// `.ask` policy will surface a prompt via `pendingDuplicate` instead
    /// of silently merging trackers.
    @discardableResult
    func addMagnet(_ uri: String, category: String?, interactive: Bool = true) async throws -> TorrentAddResult {
        guard let runtime else {
            throw TorrentEngineError.addFailed("runtime not ready")
        }
        let mode = Self.bridgePolicy(settings.duplicateTorrentPolicy)
        let result = try await runtime.engine.addMagnet(
            uri,
            category: category,
            policy: mode,
            interactive: interactive
        )
        if case let .duplicatePrompt(hash, trackers) = result {
            self.pendingDuplicate = PendingDuplicate(
                infoHash: hash,
                source: .magnet(uri: uri, category: category),
                incomingTrackers: trackers
            )
        }
        await refreshFast()
        return result
    }

    @discardableResult
    func addTorrentFile(at url: URL, category: String?, interactive: Bool = true) async throws -> TorrentAddResult {
        guard let runtime else {
            throw TorrentEngineError.addFailed("runtime not ready")
        }
        let mode = Self.bridgePolicy(settings.duplicateTorrentPolicy)
        let result = try await runtime.engine.addTorrentFile(
            at: url,
            category: category,
            policy: mode,
            interactive: interactive
        )
        if case let .duplicatePrompt(hash, trackers) = result {
            self.pendingDuplicate = PendingDuplicate(
                infoHash: hash,
                source: .torrentFile(url: url, category: category),
                incomingTrackers: trackers
            )
        }
        await refreshFast()
        return result
    }

    private static func bridgePolicy(_ p: DuplicateTorrentPolicy) -> DuplicatePolicyMode {
        switch p {
        case .ignore:         return .ignore
        case .mergeTrackers:  return .mergeTrackers
        case .ask:            return .ask
        }
    }

    /// Resolve a pending duplicate-prompt by merging the incoming
    /// trackers into the existing torrent.
    func resolvePendingDuplicateByMerging() async {
        guard let pending = pendingDuplicate, let runtime else { return }
        _ = await runtime.engine.addTrackers(pending.incomingTrackers, to: pending.infoHash)
        pendingDuplicate = nil
        await refreshFast()
    }

    /// Resolve a pending duplicate-prompt by ignoring the re-add.
    func dismissPendingDuplicate() {
        pendingDuplicate = nil
    }

    func pause(hash: String) async {
        guard let runtime else { return }
        _ = await runtime.engine.pause(infoHash: hash)
        await refreshFast()
    }

    func resume(hash: String) async {
        guard let runtime else { return }
        _ = await runtime.engine.resume(infoHash: hash)
        await refreshFast()
    }

    /// "Force Resume" / "Force Download" — bypass libtorrent's queueing
    /// system for this torrent so it runs regardless of active-* caps.
    func forceResume(hash: String) async {
        guard let runtime else { return }
        _ = await runtime.engine.forceResume(infoHash: hash)
        await refreshFast()
    }

    func remove(hash: String, deleteFiles: Bool) async {
        guard let runtime else { return }
        _ = await runtime.engine.remove(infoHash: hash, deleteFiles: deleteFiles)
        await refreshFast()
    }

    func reannounce(hash: String) async {
        guard let runtime else { return }
        _ = await runtime.engine.reannounce(infoHash: hash)
    }

    /// Force libtorrent to re-hash the torrent's on-disk files and
    /// reconcile pieces. Equivalent to qBittorrent's "Force recheck".
    func forceRecheck(hash: String) async {
        guard let runtime else { return }
        _ = await runtime.engine.forceRecheck(infoHash: hash)
        await refreshFast()
    }

    /// Merge a list of tracker URLs into an existing torrent. Duplicates
    /// are silently ignored by libtorrent.
    @discardableResult
    func addTrackers(_ trackers: [String], to hash: String) async -> Int {
        guard let runtime else { return 0 }
        let added = await runtime.engine.addTrackers(trackers, to: hash)
        await refreshFast()
        return added
    }

    /// Reveal a torrent's save path (or a specific file within it) in
    /// Finder. Used by the Torrents right-click "Open in Finder" action.
    func openInFinder(hash: String) {
        guard let torrent = torrents.first(where: { $0.infoHash == hash }) else {
            return
        }
        let savePathURL = URL(fileURLWithPath: torrent.savePath, isDirectory: true)
        // If the torrent has a top-level file or folder matching its
        // name, reveal that specifically so the user sees the content
        // highlighted rather than the whole library folder.
        let candidate = savePathURL.appendingPathComponent(torrent.name)
        if FileManager.default.fileExists(atPath: candidate.path) {
            NSWorkspace.shared.activateFileViewerSelecting([candidate])
            return
        }
        if FileManager.default.fileExists(atPath: savePathURL.path) {
            NSWorkspace.shared.open(savePathURL)
            return
        }
        // Last resort: open the category save path if we know it.
        if let categoryName = torrent.category,
           let category = categories.first(where: { $0.name == categoryName }) {
            NSWorkspace.shared.open(URL(fileURLWithPath: category.savePath, isDirectory: true))
        }
    }

    /// Copy a torrent's magnet URI to the pasteboard. Used from the
    /// Torrents right-click context menu.
    func copyMagnet(hash: String) async {
        guard let runtime else { return }
        // libtorrent can reconstruct a magnet from a live torrent_handle.
        // The shim exposes this via stats(forInfoHash:).magnetURI, but
        // for simplicity we stitch one from known fields when the shim
        // API isn't available.
        if let magnet = await runtime.engine.magnetLink(for: hash) {
            let pb = NSPasteboard.general
            pb.clearContents()
            pb.setString(magnet, forType: .string)
        }
    }

    func cyclePort() async {
        guard let runtime else { return }
        await runtime.portWatcher.forceCycle(reason: "native UI")
    }

    func saveCategory(_ category: Persistence.Category) async {
        guard let runtime else { return }
        await runtime.store.upsertCategory(category)
        await runtime.engine.registerBlockedExtensions(category.blockedExtensions, forCategory: category.name)
        await refreshAll()
    }

    func deleteCategory(named name: String) async {
        guard let runtime else { return }
        await runtime.store.removeCategory(named: name)
        await refreshAll()
    }

    /// Assign (or clear) a torrent's category and optionally move its files
    /// to the destination category's save path. Returns whether the storage
    /// move was kicked off and the resolved target path (for UI feedback).
    @discardableResult
    func changeCategory(
        hash: String,
        to category: String?,
        moveFiles: Bool
    ) async -> (moved: Bool, targetPath: String?) {
        guard let runtime else { return (false, nil) }
        let result = await runtime.engine.setCategory(category, for: hash, moveFiles: moveFiles)
        await runtime.store.noteCategoryForHash(hash, category: category)
        await refreshFast()
        return (result.moved, result.targetPath)
    }

    /// Edit a category's save path and, if requested, move every torrent
    /// tagged with that category to the new location. Returns the list of
    /// info hashes that were actually moved.
    @discardableResult
    func applyCategoryPathChange(
        category: String,
        newPath: String,
        moveFiles: Bool
    ) async -> [String] {
        guard let runtime else { return [] }
        var updated = await runtime.store.category(named: category)
            ?? Persistence.Category(name: category, savePath: newPath)
        updated.savePath = newPath
        await runtime.store.upsertCategory(updated)
        var moved: [String] = []
        if moveFiles {
            moved = await runtime.engine.moveCategoryMembers(category, to: newPath)
        }
        await refreshAll()
        return moved
    }

    func saveSettings(_ newSettings: Persistence.Settings) async {
        guard let runtime else { return }
        await runtime.store.replaceSettings(newSettings)
        await runtime.applyNetworkSettings()
        await refreshAll()
        if let delegate = NSApp.delegate as? AppDelegate {
            delegate.applyInterfacePreferences()
        }
    }

    func clearHealthIssue(hash: String) async {
        guard let runtime else { return }
        await runtime.healthMonitor.clearIssue(hash: hash)
        await refreshFast()
    }

    func runRecovery(hash: String, action: RecoveryAction? = nil) async throws {
        guard let runtime else { return }
        _ = try await runtime.recoveryCenter.runRecovery(for: hash, action: action)
        await refreshAll()
    }

    func retryPostProcessor(hash: String) async throws {
        guard let runtime else { return }
        _ = try await runtime.postProcessor.retry(infoHash: hash)
        await refreshAll()
    }

    func recheckDiskSpace() async {
        guard let runtime else { return }
        await runtime.diskSpaceMonitor.forceEvaluate()
        await refreshFast()
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
        await refreshAll()
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
