//
//  TorrentEngine.swift
//  Controllarr — Phase 0 PoC
//
//  Thin Swift wrapper over LibtorrentShim. Keeps the Objective-C types
//  contained and presents Sendable Swift value types to the rest of the
//  app. Everything above this line should never need to know libtorrent
//  exists.
//

import Foundation
import LibtorrentShim

public enum TorrentState: Int, Sendable {
    case unknown             = 0
    case checkingFiles       = 1
    case downloadingMetadata = 2
    case downloading         = 3
    case finished            = 4
    case seeding             = 5
    case checkingResume      = 6

    init(_ raw: CTRLTorrentState) {
        self = TorrentState(rawValue: raw.rawValue) ?? .unknown
    }
}

public struct TorrentStats: Sendable, Identifiable {
    public var id: String { infoHash }
    public let name: String
    public let infoHash: String
    public let progress: Float
    public let state: TorrentState
    public let downloadRate: Int64
    public let uploadRate: Int64
    public let totalWanted: Int64
    public let totalDone: Int64
    public let numPeers: Int
    public let numSeeds: Int
}

public enum TorrentEngineError: Error {
    case addFailed(String)
}

/// Entry point. Wraps the Obj-C session in a Swift-friendly API. Not an
/// actor yet — Phase 0 calls this from a single thread. When we go
/// multi-threaded in Phase 1 we'll wrap this in an actor.
public final class TorrentEngine {

    private let session: CTRLSession

    public init(savePath: URL, listenPort: UInt16 = 6881) {
        self.session = CTRLSession(savePath: savePath.path, listenPort: listenPort)
    }

    public func addMagnet(_ uri: String) throws {
        // Swift auto-imports `-addMagnet:error:` as a throwing method.
        do {
            try session.addMagnet(uri)
        } catch {
            throw TorrentEngineError.addFailed(error.localizedDescription)
        }
    }

    public func addTorrentFile(at path: URL) throws {
        do {
            try session.addTorrentFile(path.path)
        } catch {
            throw TorrentEngineError.addFailed(error.localizedDescription)
        }
    }

    public func pollStats() -> [TorrentStats] {
        let raw = session.pollStats()
        return raw.map { s in
            TorrentStats(
                name: s.name,
                infoHash: s.infoHash,
                progress: s.progress,
                state: TorrentState(s.state),
                downloadRate: s.downloadRate,
                uploadRate: s.uploadRate,
                totalWanted: s.totalWanted,
                totalDone: s.totalDone,
                numPeers: Int(s.numPeers),
                numSeeds: Int(s.numSeeds)
            )
        }
    }

    public func drainAlerts() {
        session.drainAlerts()
    }

    public func shutdown() {
        session.shutdown()
    }
}
