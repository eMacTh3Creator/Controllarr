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

/// Callback the engine uses to resolve a category name to its save path,
/// without taking a hard dependency on the Persistence module. Closure
/// form so any layer above the engine can supply one without conforming
/// to a protocol.
public typealias CategoryResolver = @Sendable (String) async -> String?

public let nullCategoryResolver: CategoryResolver = { _ in nil }

// MARK: - Engine

public actor TorrentEngine {

    public let defaultSavePath: URL
    public private(set) var listenPort: UInt16

    private let session: CTRLSession
    private let resumeDir: URL
    private var categoryByHash: [String: String] = [:]
    private let resolver: CategoryResolver

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
        // Restore any previously-persisted torrents.
        self.session.loadResumeData(from: resumeDataDirectory.path)
    }

    // MARK: Adding

    public func addMagnet(_ uri: String, category: String? = nil) async throws -> String {
        let savePath = try await resolvedSavePath(for: category)
        do {
            try session.addMagnet(uri, savePath: savePath)
        } catch {
            throw TorrentEngineError.addFailed(error.localizedDescription)
        }
        // libtorrent doesn't return the hash from parse_magnet_uri via the
        // Obj-C bridge; walk the snapshot for a freshly-added torrent.
        let hash = latestHashFromSnapshot()
        if let hash, let category { categoryByHash[hash] = category }
        return hash ?? ""
    }

    public func addTorrentFile(at path: URL, category: String? = nil) async throws -> String {
        let savePath = try await resolvedSavePath(for: category)
        do {
            try session.addTorrentFile(path.path, savePath: savePath)
        } catch {
            throw TorrentEngineError.addFailed(error.localizedDescription)
        }
        let hash = latestHashFromSnapshot()
        if let hash, let category { categoryByHash[hash] = category }
        return hash ?? ""
    }

    private func resolvedSavePath(for category: String?) async throws -> String? {
        guard let category else { return nil }
        return await resolver(category)
    }

    private func latestHashFromSnapshot() -> String? {
        let all = session.pollStats()
        // Heuristic: whichever torrent has the most recent addedDate.
        return all.max(by: { $0.addedDate < $1.addedDate })?.infoHash
    }

    // MARK: Mutating

    @discardableResult
    public func pause(infoHash: String) -> Bool { session.pauseTorrent(infoHash) }

    @discardableResult
    public func resume(infoHash: String) -> Bool { session.resumeTorrent(infoHash) }

    @discardableResult
    public func remove(infoHash: String, deleteFiles: Bool) -> Bool {
        categoryByHash.removeValue(forKey: infoHash)
        return session.removeTorrent(infoHash, deleteFiles: deleteFiles)
    }

    @discardableResult
    public func move(infoHash: String, to path: URL) -> Bool {
        session.moveTorrent(infoHash, toPath: path.path)
    }

    public func setCategory(_ category: String?, for infoHash: String) {
        if let category { categoryByHash[infoHash] = category }
        else { categoryByHash.removeValue(forKey: infoHash) }
    }

    // MARK: Reading

    public func pollStats() -> [TorrentStats] {
        session.pollStats().map { bridge($0) }
    }

    public func stats(for infoHash: String) -> TorrentStats? {
        guard let raw = session.stats(forInfoHash: infoHash) else { return nil }
        return bridge(raw)
    }

    public func sessionStats() -> SessionStats {
        let s = session.sessionStats()
        return SessionStats(
            downloadRate: s.downloadRate,
            uploadRate: s.uploadRate,
            totalDownloaded: s.totalBytesDownloaded,
            totalUploaded: s.totalBytesUploaded,
            numTorrents: Int(s.numTorrents),
            numPeersConnected: Int(s.numPeersConnected),
            hasIncomingConnections: s.hasIncomingConnections,
            listenPort: s.listenPort
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
    }

    public func forceReannounceAll() {
        session.forceReannounceAll()
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
    public func restoreCategories(_ map: [String: String]) { categoryByHash = map }
}
