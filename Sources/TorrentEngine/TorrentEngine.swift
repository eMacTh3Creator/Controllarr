//
//  TorrentEngine.swift
//  Controllarr — Phase 1
//
//  Actor-based Swift wrapper around LibtorrentShim. Adds the concept of
//  *categories* (which libtorrent itself does not have) as a metadata
//  overlay: category name -> save path + dangerous-file filter. Category
//  metadata is owned by the Persistence module; the engine just reads it
//  through `CategoryResolver`.
//

import Foundation
import LibtorrentShim

// MARK: - Value types

public enum TorrentState: Int, Sendable, Codable {
    case unknown             = 0
    case checkingFiles       = 1
    case downloadingMetadata = 2
    case downloading         = 3
    case finished            = 4
    case seeding             = 5
    case checkingResume      = 6
    case paused              = 7

    init(_ raw: CTRLTorrentState) {
        self = TorrentState(rawValue: raw.rawValue) ?? .unknown
    }
}

public struct TorrentStats: Sendable, Identifiable, Codable {
    public var id: String { infoHash }
    public let name: String
    public let infoHash: String
    public let savePath: String
    public let progress: Float
    public let state: TorrentState
    public let paused: Bool
    public let downloadRate: Int64
    public let uploadRate: Int64
    public let totalWanted: Int64
    public let totalDone: Int64
    public let totalDownload: Int64
    public let totalUpload: Int64
    public let ratio: Double
    public let numPeers: Int
    public let numSeeds: Int
    public let etaSeconds: Int
    public let addedDate: Date
    /// Optional overlay: Controllarr's category name, if one was set when
    /// the torrent was added.
    public var category: String?
}

public struct SessionStats: Sendable, Codable {
    public let downloadRate: Int64
    public let uploadRate: Int64
    public let totalDownloaded: Int64
    public let totalUploaded: Int64
    public let numTorrents: Int
    public let numPeersConnected: Int
    public let hasIncomingConnections: Bool
    public let listenPort: UInt16

    public init(
        downloadRate: Int64,
        uploadRate: Int64,
        totalDownloaded: Int64,
        totalUploaded: Int64,
        numTorrents: Int,
        numPeersConnected: Int,
        hasIncomingConnections: Bool,
        listenPort: UInt16
    ) {
        self.downloadRate = downloadRate
        self.uploadRate = uploadRate
        self.totalDownloaded = totalDownloaded
        self.totalUploaded = totalUploaded
        self.numTorrents = numTorrents
        self.numPeersConnected = numPeersConnected
        self.hasIncomingConnections = hasIncomingConnections
        self.listenPort = listenPort
    }
}

public struct TrackerInfo: Sendable, Identifiable, Codable {
    public var id: String { url }
    public let url: String
    public let tier: Int
    public let numPeers: Int
    public let numSeeds: Int
    public let numLeechers: Int
    public let numDownloaded: Int
    public let message: String
    public let status: Int // 0=disabled, 1=not_contacted, 2=working, 3=updating, 4=error

    public init(
        url: String,
        tier: Int,
        numPeers: Int,
        numSeeds: Int,
        numLeechers: Int,
        numDownloaded: Int,
        message: String,
        status: Int
    ) {
        self.url = url
        self.tier = tier
        self.numPeers = numPeers
        self.numSeeds = numSeeds
        self.numLeechers = numLeechers
        self.numDownloaded = numDownloaded
        self.message = message
        self.status = status
    }
}

public struct PeerInfo: Sendable, Identifiable, Codable {
    public var id: String { "\(ip):\(port)" }
    public let ip: String
    public let port: Int
    public let client: String
    public let progress: Float
    public let downloadRate: Int64
    public let uploadRate: Int64
    public let totalDownload: Int64
    public let totalUpload: Int64
    public let flags: String
    public let country: String

    public init(
        ip: String,
        port: Int,
        client: String,
        progress: Float,
        downloadRate: Int64,
        uploadRate: Int64,
        totalDownload: Int64,
        totalUpload: Int64,
        flags: String,
        country: String
    ) {
        self.ip = ip
        self.port = port
        self.client = client
        self.progress = progress
        self.downloadRate = downloadRate
        self.uploadRate = uploadRate
        self.totalDownload = totalDownload
        self.totalUpload = totalUpload
        self.flags = flags
        self.country = country
    }
}

public struct FileInfo: Sendable, Identifiable, Codable {
    public var id: Int { index }
    public let index: Int
    public let name: String
    public let size: Int64
    public let priority: Int

    public init(index: Int, name: String, size: Int64, priority: Int) {
        self.index = index
        self.name = name
        self.size = size
        self.priority = priority
    }
}

public enum TorrentEngineError: Error, LocalizedError {
    case addFailed(String)
    case notFound(String)

    public var errorDescription: String? {
        switch self {
        case .addFailed(let m): return "add failed: \(m)"
        case .notFound(let h):  return "torrent not found: \(h)"
        }
    }
}

/// Outcome of an add-request. Differentiates new adds from duplicates so
/// callers (WebUI, *arr, native UI) can react appropriately — e.g. the
/// native UI can surface a duplicate-prompt sheet, while qBittorrent-API
/// callers just return 200 OK.
public enum TorrentAddResult: Sendable {
    /// A brand-new torrent was added. Payload is the info-hash.
    case added(infoHash: String)
    /// An incoming add matched an existing info-hash. Policy was
    /// `.ignore` — nothing changed.
    case duplicateIgnored(infoHash: String)
    /// An incoming add matched an existing info-hash. Policy was
    /// `.mergeTrackers` (or `.ask` falling back to merge for
    /// non-interactive callers) — `added` new trackers were unioned
    /// into the existing torrent.
    case duplicateMergedTrackers(infoHash: String, added: Int)
    /// An incoming add matched an existing info-hash. Policy is `.ask`
    /// and the caller is interactive — UI should prompt the operator
    /// with `incomingTrackers`.
    case duplicatePrompt(infoHash: String, incomingTrackers: [String])

    public var infoHash: String {
        switch self {
        case .added(let h),
             .duplicateIgnored(let h),
             .duplicateMergedTrackers(let h, _),
             .duplicatePrompt(let h, _):
            return h
        }
    }

    public var isDuplicate: Bool {
        if case .added = self { return false }
        return true
    }
}

/// Policy value passed to `addMagnet` / `addTorrentFile` so callers can
/// pick the runtime behavior without the engine having to read
/// `Settings`. Mirrors `DuplicateTorrentPolicy` — kept separate to avoid
/// a Persistence dependency in the engine module.
public enum DuplicatePolicyMode: Sendable {
    case ignore
    case mergeTrackers
    case ask
}

/// Callback the engine uses to resolve a category name to its save path,
/// without taking a hard dependency on the Persistence module. Closure
/// form so any layer above the engine can supply one without conforming
/// to a protocol.
public typealias CategoryResolver = @Sendable (String) async -> String?

public let nullCategoryResolver: CategoryResolver = { _ in nil }

// MARK: - Engine

public actor TorrentEngine {

    struct CachedSnapshot {
        let torrents: [TorrentStats]
        let byHash: [String: TorrentStats]
        let session: SessionStats
        let capturedAt: Date
    }

    public let defaultSavePath: URL
    public private(set) var listenPort: UInt16

    private let session: CTRLSession
    private let resumeDir: URL
    private var categoryByHash: [String: String] = [:]
    private let resolver: CategoryResolver

    /// True once Controllarr has applied dangerous-file filtering to a
    /// given info hash. Keyed on info hash. Set lazily on the first
    /// pollStats tick where the torrent's metadata is available.
    private var fileFilterApplied: Set<String> = []
    /// Blocked extensions, lowercased without the dot, keyed by category
    /// name. Populated from Persistence at add-time so the engine can
    /// apply priorities without needing another async round-trip.
    private var blockedExtensionsByCategory: [String: [String]] = [:]
    private var cachedSnapshot: CachedSnapshot?
    private let snapshotCacheTTL: TimeInterval = 0.5

    public init(
        defaultSavePath: URL,
        resumeDataDirectory: URL,
        listenPort: UInt16,
        resolver: @escaping CategoryResolver = nullCategoryResolver
    ) {
        self.defaultSavePath = defaultSavePath
        self.resumeDir = resumeDataDirectory
        self.listenPort = listenPort
        self.resolver = resolver

        try? FileManager.default.createDirectory(at: defaultSavePath, withIntermediateDirectories: true)
        try? FileManager.default.createDirectory(at: resumeDataDirectory, withIntermediateDirectories: true)

        self.session = CTRLSession(
            savePath: defaultSavePath.path,
            listenPort: listenPort,
            bindAllInterfaces: false
        )
        // Point the shim at the resume directory so add-time sidecars
        // (.magnet / .torrent / .path) and .fastresume files all live
        // side-by-side. Must happen BEFORE loadResumeData so the restore
        // pass can also see sidecars.
        self.session.setMetadataDirectory(resumeDataDirectory.path)
        // Restore any previously-persisted torrents.
        self.session.loadResumeData(from: resumeDataDirectory.path)
    }

    // MARK: Adding

    public func addMagnet(_ uri: String, category: String? = nil, explicitSavePath: String? = nil) async throws -> String {
        let savePath: String?
        if let explicitSavePath {
            savePath = explicitSavePath
        } else {
            savePath = try await resolvedSavePath(for: category)
        }
        do {
            try session.addMagnet(uri, savePath: savePath)
        } catch {
            throw TorrentEngineError.addFailed(error.localizedDescription)
        }
        invalidateSnapshotCache()
        // libtorrent doesn't return the hash from parse_magnet_uri via the
        // Obj-C bridge; walk the snapshot for a freshly-added torrent.
        let hash = latestHashFromSnapshot()
        if let hash, let category { categoryByHash[hash] = category }
        return hash ?? ""
    }

    public func addTorrentFile(at path: URL, category: String? = nil, explicitSavePath: String? = nil) async throws -> String {
        let savePath: String?
        if let explicitSavePath {
            savePath = explicitSavePath
        } else {
            savePath = try await resolvedSavePath(for: category)
        }
        do {
            try session.addTorrentFile(path.path, savePath: savePath)
        } catch {
            throw TorrentEngineError.addFailed(error.localizedDescription)
        }
        invalidateSnapshotCache()
        let hash = latestHashFromSnapshot()
        if let hash, let category { categoryByHash[hash] = category }
        return hash ?? ""
    }

    // MARK: Adding (duplicate-aware)

    /// Duplicate-aware magnet add. Checks info-hash against the current
    /// session before dispatching, and applies the given policy if the
    /// hash is already present.
    ///
    /// - Parameters:
    ///   - uri: magnet: URI
    ///   - category: optional category name to associate with the torrent
    ///   - explicitSavePath: overrides category-resolved save path
    ///   - policy: what to do on duplicate
    ///   - interactive: whether the caller can surface a prompt. Non-
    ///     interactive callers (qBittorrent API, *arr, daemon) receive
    ///     `.duplicateMergedTrackers` instead of `.duplicatePrompt` when
    ///     policy is `.ask`.
    public func addMagnet(
        _ uri: String,
        category: String? = nil,
        explicitSavePath: String? = nil,
        policy: DuplicatePolicyMode,
        interactive: Bool
    ) async throws -> TorrentAddResult {
        guard let incomingHash = session.infoHash(forMagnet: uri),
              !incomingHash.isEmpty else {
            // Couldn't parse info-hash — fall through to the legacy path
            // which will surface the real parse error.
            let h = try await addMagnet(uri, category: category, explicitSavePath: explicitSavePath)
            return .added(infoHash: h)
        }

        if session.hasTorrent(incomingHash) {
            let incomingTrackers = session.trackers(inMagnet: uri)
            return applyDuplicatePolicy(
                infoHash: incomingHash,
                incomingTrackers: incomingTrackers,
                policy: policy,
                interactive: interactive
            )
        }

        let h = try await addMagnet(uri, category: category, explicitSavePath: explicitSavePath)
        return .added(infoHash: h)
    }

    /// Duplicate-aware .torrent file add. Same semantics as
    /// `addMagnet(…, policy:interactive:)`.
    public func addTorrentFile(
        at path: URL,
        category: String? = nil,
        explicitSavePath: String? = nil,
        policy: DuplicatePolicyMode,
        interactive: Bool
    ) async throws -> TorrentAddResult {
        guard let incomingHash = session.infoHash(forTorrentFile: path.path),
              !incomingHash.isEmpty else {
            let h = try await addTorrentFile(at: path, category: category, explicitSavePath: explicitSavePath)
            return .added(infoHash: h)
        }

        if session.hasTorrent(incomingHash) {
            let incomingTrackers = session.trackers(inTorrentFile: path.path)
            return applyDuplicatePolicy(
                infoHash: incomingHash,
                incomingTrackers: incomingTrackers,
                policy: policy,
                interactive: interactive
            )
        }

        let h = try await addTorrentFile(at: path, category: category, explicitSavePath: explicitSavePath)
        return .added(infoHash: h)
    }

    private func applyDuplicatePolicy(
        infoHash: String,
        incomingTrackers: [String],
        policy: DuplicatePolicyMode,
        interactive: Bool
    ) -> TorrentAddResult {
        switch policy {
        case .ignore:
            return .duplicateIgnored(infoHash: infoHash)
        case .mergeTrackers:
            let added = session.addTrackers(toTorrent: infoHash, trackers: incomingTrackers)
            if added > 0 { invalidateSnapshotCache() }
            return .duplicateMergedTrackers(infoHash: infoHash, added: Int(added))
        case .ask:
            if interactive {
                return .duplicatePrompt(infoHash: infoHash, incomingTrackers: incomingTrackers)
            }
            // Non-interactive caller: fall back to tracker merge so the
            // re-add still accomplishes *something*.
            let added = session.addTrackers(toTorrent: infoHash, trackers: incomingTrackers)
            if added > 0 { invalidateSnapshotCache() }
            return .duplicateMergedTrackers(infoHash: infoHash, added: Int(added))
        }
    }

    /// Union-merge the given tracker URLs into an existing torrent.
    /// Returns the number of trackers actually added (duplicates are
    /// skipped).
    @discardableResult
    public func addTrackers(_ trackers: [String], to infoHash: String) -> Int {
        let added = Int(session.addTrackers(toTorrent: infoHash, trackers: trackers))
        if added > 0 { invalidateSnapshotCache() }
        return added
    }

    /// Force a libtorrent piece-hash recheck against on-disk files.
    /// Equivalent to qBittorrent's "Force recheck". Useful when the user
    /// already has most of the data on disk and wants to skip
    /// redownloading — libtorrent will hash every file and only the
    /// pieces that don't match get queued.
    @discardableResult
    public func forceRecheck(infoHash: String) -> Bool {
        let ok = session.forceRecheckTorrent(infoHash)
        if ok { invalidateSnapshotCache() }
        return ok
    }

    /// Returns true if the session already contains a torrent with the
    /// given info-hash. Useful for UI-level duplicate checks.
    public func hasTorrent(infoHash: String) -> Bool {
        session.hasTorrent(infoHash)
    }

    /// Parse an incoming magnet URI and return its info-hash without
    /// adding it to the session. Returns nil if the URI is malformed.
    public func infoHash(forMagnet uri: String) -> String? {
        session.infoHash(forMagnet: uri)
    }

    /// Same as `infoHash(forMagnet:)` for .torrent files.
    public func infoHash(forTorrentFile path: URL) -> String? {
        session.infoHash(forTorrentFile: path.path)
    }

    /// Reconstruct a magnet: URI for an already-added torrent. Returns
    /// nil if metadata isn't available.
    public func magnetLink(for infoHash: String) -> String? {
        session.makeMagnet(forTorrent: infoHash)
    }

    private func resolvedSavePath(for category: String?) async throws -> String? {
        guard let category else { return nil }
        return await resolver(category)
    }

    private func latestHashFromSnapshot() -> String? {
        // Heuristic: whichever torrent has the most recent addedDate.
        materializeSnapshot(forceRefresh: true)
            .torrents
            .max(by: { $0.addedDate < $1.addedDate })?
            .infoHash
    }

    // MARK: Mutating

    @discardableResult
    public func pause(infoHash: String) -> Bool {
        let didPause = session.pauseTorrent(infoHash)
        if didPause { invalidateSnapshotCache() }
        return didPause
    }

    @discardableResult
    public func resume(infoHash: String) -> Bool {
        let didResume = session.resumeTorrent(infoHash)
        if didResume { invalidateSnapshotCache() }
        return didResume
    }

    /// "Force Download" / "Force Resume" — resume a torrent and take it out
    /// of the auto-managed pool so libtorrent's queue system can never
    /// silently re-pause it. This is what you want for a torrent the user
    /// explicitly clicked Force Resume on.
    @discardableResult
    public func forceResume(infoHash: String) -> Bool {
        let didResume = session.forceResumeTorrent(infoHash)
        if didResume { invalidateSnapshotCache() }
        return didResume
    }

    /// Apply the operator's torrent-queueing configuration (from Settings)
    /// to the libtorrent session. When `enabled` is false the active-* caps
    /// are raised to 10,000 so queueing never auto-pauses anything.
    public func applyQueueing(enabled: Bool, activeDownloads: Int, activeSeeds: Int, activeLimit: Int) {
        session.setQueueingEnabled(
            enabled,
            activeDownloads: Int32(activeDownloads),
            activeSeeds: Int32(activeSeeds),
            activeLimit: Int32(activeLimit)
        )
    }

    @discardableResult
    public func remove(infoHash: String, deleteFiles: Bool) -> Bool {
        categoryByHash.removeValue(forKey: infoHash)
        let didRemove = session.removeTorrent(infoHash, deleteFiles: deleteFiles)
        if didRemove { invalidateSnapshotCache() }
        return didRemove
    }

    @discardableResult
    public func move(infoHash: String, to path: URL) -> Bool {
        let didMove = session.moveTorrent(infoHash, toPath: path.path)
        if didMove { invalidateSnapshotCache() }
        return didMove
    }

    public func setCategory(_ category: String?, for infoHash: String) {
        if let category { categoryByHash[infoHash] = category }
        else { categoryByHash.removeValue(forKey: infoHash) }
        invalidateSnapshotCache()
    }

    /// Assign a category to a torrent and optionally move its on-disk files
    /// to the category's save path. Returns true if the category was applied;
    /// `moved` is true when a move_storage was kicked off.
    @discardableResult
    public func setCategory(
        _ category: String?,
        for infoHash: String,
        moveFiles: Bool
    ) async -> (applied: Bool, moved: Bool, targetPath: String?) {
        setCategory(category, for: infoHash)
        guard moveFiles, let category,
              let target = await resolver(category),
              !target.isEmpty else {
            return (true, false, nil)
        }
        // Skip if the torrent's current save path already matches.
        if let current = stats(for: infoHash)?.savePath, current == target {
            return (true, false, target)
        }
        try? FileManager.default.createDirectory(
            atPath: target, withIntermediateDirectories: true
        )
        let ok = move(infoHash: infoHash, to: URL(fileURLWithPath: target))
        return (true, ok, target)
    }

    /// Move every torrent currently tagged with the given category to the
    /// specified new path. Used when a category's save path is edited and
    /// the operator chooses to reorganize the library.
    @discardableResult
    public func moveCategoryMembers(_ category: String, to newPath: String) async -> [String] {
        try? FileManager.default.createDirectory(
            atPath: newPath, withIntermediateDirectories: true
        )
        let targetURL = URL(fileURLWithPath: newPath)
        var moved: [String] = []
        for torrent in pollStats() where categoryByHash[torrent.infoHash] == category {
            guard torrent.savePath != newPath else { continue }
            if move(infoHash: torrent.infoHash, to: targetURL) {
                moved.append(torrent.infoHash)
            }
        }
        return moved
    }

    /// Record a category's blocked extension list so the engine can
    /// apply libtorrent file priorities when metadata arrives.
    public func registerBlockedExtensions(_ extensions: [String], forCategory category: String) {
        let cleaned = extensions.map { ext -> String in
            var e = ext.lowercased()
            if e.hasPrefix(".") { e.removeFirst() }
            return e
        }.filter { !$0.isEmpty }
        if cleaned.isEmpty {
            blockedExtensionsByCategory.removeValue(forKey: category)
        } else {
            blockedExtensionsByCategory[category] = cleaned
        }
    }

    /// List the files in a torrent, or nil if metadata isn't available yet.
    public func fileNames(for infoHash: String) -> [String]? {
        session.fileNames(forInfoHash: infoHash)
    }

    /// Apply per-file download priorities directly. 0 = skip, 4 = normal.
    @discardableResult
    public func setFilePriorities(_ priorities: [Int], for infoHash: String) -> Bool {
        let didSet = session.setFilePriorities(priorities.map { NSNumber(value: $0) }, forInfoHash: infoHash)
        if didSet { invalidateSnapshotCache() }
        return didSet
    }

    /// Ask libtorrent to immediately re-announce a single torrent.
    @discardableResult
    public func reannounce(infoHash: String) -> Bool {
        session.reannounceTorrent(infoHash)
    }

    /// Return the list of trackers for a torrent.
    public func trackers(for infoHash: String) -> [TrackerInfo]? {
        guard let raw = session.trackers(forInfoHash: infoHash) else { return nil }
        return raw.map { t in
            TrackerInfo(
                url: t.url,
                tier: Int(t.tier),
                numPeers: Int(t.numPeers),
                numSeeds: Int(t.numSeeds),
                numLeechers: Int(t.numLeechers),
                numDownloaded: Int(t.numDownloaded),
                message: t.message,
                status: Int(t.status)
            )
        }
    }

    /// Return the list of connected peers for a torrent.
    public func peers(for infoHash: String) -> [PeerInfo]? {
        guard let raw = session.peers(forInfoHash: infoHash) else { return nil }
        return raw.map { p in
            PeerInfo(
                ip: p.ip,
                port: Int(p.port),
                client: p.client,
                progress: p.progress,
                downloadRate: p.downloadRate,
                uploadRate: p.uploadRate,
                totalDownload: p.totalDownload,
                totalUpload: p.totalUpload,
                flags: p.flags,
                country: p.country
            )
        }
    }

    /// Return per-file info (name, size, priority) for a torrent.
    public func fileInfo(for infoHash: String) -> [FileInfo]? {
        guard let raw = session.fileInfo(forInfoHash: infoHash) else { return nil }
        return raw.enumerated().map { (idx, dict) in
            FileInfo(
                index: idx,
                name: dict["name"] as? String ?? "",
                size: (dict["size"] as? NSNumber)?.int64Value ?? 0,
                priority: (dict["priority"] as? NSNumber)?.intValue ?? 4
            )
        }
    }

    /// Walk current torrents and, for any whose metadata has arrived and
    /// whose category has blocked extensions, apply file priorities to
    /// skip the blocked files. Idempotent — each hash is only processed
    /// once. Called on every poll tick by the runtime.
    public func applyPendingFileFilters() {
        for torrent in materializeSnapshot(forceRefresh: true).torrents {
            let hash = torrent.infoHash
            if fileFilterApplied.contains(hash) { continue }
            guard let category = categoryByHash[hash],
                  let blocked = blockedExtensionsByCategory[category],
                  !blocked.isEmpty else {
                // Nothing to filter, but mark applied so we don't retry.
                if categoryByHash[hash] == nil || blockedExtensionsByCategory[categoryByHash[hash] ?? ""] == nil {
                    fileFilterApplied.insert(hash)
                }
                continue
            }
            guard let files = session.fileNames(forInfoHash: hash) else {
                // Metadata not yet available — try again next tick.
                continue
            }
            let priorities: [NSNumber] = files.map { file -> NSNumber in
                let ext = (file as NSString).pathExtension.lowercased()
                return blocked.contains(ext) ? NSNumber(value: 0) : NSNumber(value: 4)
            }
            _ = session.setFilePriorities(priorities, forInfoHash: hash)
            fileFilterApplied.insert(hash)
        }
        invalidateSnapshotCache()
    }

    // MARK: Reading

    public func pollStats() -> [TorrentStats] {
        materializeSnapshot().torrents
    }

    public func stats(for infoHash: String) -> TorrentStats? {
        if let cached = cachedSnapshot,
           Date().timeIntervalSince(cached.capturedAt) <= snapshotCacheTTL,
           let torrent = cached.byHash[infoHash] {
            return torrent
        }
        guard let raw = session.stats(forInfoHash: infoHash) else { return nil }
        return bridge(raw)
    }

    public func sessionStats() -> SessionStats {
        materializeSnapshot().session
    }

    static func summarizeSession(torrents: [TorrentStats], listenPort: UInt16) -> SessionStats {
        SessionStats(
            downloadRate: torrents.reduce(into: 0) { $0 += $1.downloadRate },
            uploadRate: torrents.reduce(into: 0) { $0 += $1.uploadRate },
            totalDownloaded: torrents.reduce(into: 0) { $0 += $1.totalDownload },
            totalUploaded: torrents.reduce(into: 0) { $0 += $1.totalUpload },
            numTorrents: torrents.count,
            numPeersConnected: torrents.reduce(into: 0) { $0 += $1.numPeers },
            hasIncomingConnections: torrents.contains(where: { $0.numPeers > 0 }),
            listenPort: listenPort
        )
    }

    private func bridge(_ s: CTRLTorrentStats) -> TorrentStats {
        TorrentStats(
            name: s.name,
            infoHash: s.infoHash,
            savePath: s.savePath,
            progress: s.progress,
            state: TorrentState(s.state),
            paused: s.paused,
            downloadRate: s.downloadRate,
            uploadRate: s.uploadRate,
            totalWanted: s.totalWanted,
            totalDone: s.totalDone,
            totalDownload: s.totalDownload,
            totalUpload: s.totalUpload,
            ratio: s.ratio,
            numPeers: Int(s.numPeers),
            numSeeds: Int(s.numSeeds),
            etaSeconds: Int(s.etaSeconds),
            addedDate: s.addedDate,
            category: categoryByHash[s.infoHash]
        )
    }

    // MARK: Listen port (the feature)

    public func setListenPort(_ port: UInt16) {
        self.listenPort = port
        session.setListenPort(port)
        invalidateSnapshotCache()
    }

    /// Directly set libtorrent's listen_interfaces string. Used by VPN
    /// monitor to bind listen to the VPN adapter IP + current port.
    public func setListenInterfaces(_ interfaces: String) {
        session.setListenInterfacesString(interfaces)
        invalidateSnapshotCache()
    }

    /// Bind all outgoing peer/tracker traffic to a specific network
    /// interface (e.g. "utun4" or "10.0.0.1"). Empty string reverts
    /// to OS default routing.
    public func setOutgoingInterface(_ name: String) {
        session.setOutgoingInterface(name)
        invalidateSnapshotCache()
    }

    /// Set global download/upload rate limits. 0 = unlimited.
    public func setRateLimits(downloadKBps: Int?, uploadKBps: Int?) {
        session.setRateLimitsDownloadKBps(Int32(downloadKBps ?? 0), uploadKBps: Int32(uploadKBps ?? 0))
        invalidateSnapshotCache()
    }

    /// Toggle DHT / PeX / LSD peer discovery. PeX is applied on next restart.
    public func setPeerDiscovery(dht: Bool, pex: Bool, lsd: Bool) {
        session.setPeerDiscoveryDHT(dht, pex: pex, lsd: lsd)
    }

    /// Apply connection-count ceilings. Pass nil/0 to leave the current value.
    public func setConnectionLimits(
        globalConnections: Int?,
        perTorrentConnections: Int?,
        globalUploads: Int?,
        perTorrentUploads: Int?
    ) {
        session.setConnectionLimitsGlobalConnections(
            Int32(globalConnections ?? 0),
            connectionsPerTorrent: Int32(perTorrentConnections ?? 0),
            globalUploads: Int32(globalUploads ?? 0),
            uploadsPerTorrent: Int32(perTorrentUploads ?? 0)
        )
    }

    public func forceReannounceAll() {
        session.forceReannounceAll()
        invalidateSnapshotCache()
    }

    // MARK: Lifecycle

    public func drainAlerts() { session.drainAlerts() }

    public func saveResumeData() {
        session.saveResumeData(to: resumeDir.path)
    }

    public func shutdown() {
        session.saveResumeData(to: resumeDir.path)
        session.shutdown()
    }

    // MARK: Direct category-map access for persistence round-trip

    public func snapshotCategories() -> [String: String] { categoryByHash }
    public func restoreCategories(_ map: [String: String]) {
        categoryByHash = map
        invalidateSnapshotCache()
    }

    private func materializeSnapshot(forceRefresh: Bool = false) -> CachedSnapshot {
        if !forceRefresh,
           let cachedSnapshot,
           Date().timeIntervalSince(cachedSnapshot.capturedAt) <= snapshotCacheTTL {
            return cachedSnapshot
        }

        let raw = session.pollStats()
        var torrents: [TorrentStats] = []
        torrents.reserveCapacity(raw.count)
        var byHash: [String: TorrentStats] = [:]
        byHash.reserveCapacity(raw.count)

        for item in raw {
            let bridged = bridge(item)
            torrents.append(bridged)
            byHash[bridged.infoHash] = bridged
        }

        let snapshot = CachedSnapshot(
            torrents: torrents,
            byHash: byHash,
            session: Self.summarizeSession(torrents: torrents, listenPort: listenPort),
            capturedAt: Date()
        )
        cachedSnapshot = snapshot
        return snapshot
    }

    private func invalidateSnapshotCache() {
        cachedSnapshot = nil
    }
}
