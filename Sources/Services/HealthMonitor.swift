//
//  HealthMonitor.swift
//  Controllarr
//
//  Watches downloading torrents for stalls (zero payload progress for N
//  minutes) and classifies the likely reason. Feeds both a rolling list
//  of active issues (consumed by the UI) and the optional auto-reannounce
//  recovery step.
//

import Foundation
import TorrentEngine
import Persistence

public actor HealthMonitor {

    public enum Reason: String, Sendable, Codable {
        /// Metadata never arrived — magnet link still fetching after
        /// an unreasonable amount of time.
        case metadataTimeout = "metadata_timeout"
        /// Active downloading torrent has had no progress and is
        /// connected to zero peers. Classic dead swarm / port blocked.
        case noPeers = "no_peers"
        /// Connected peers but progress hasn't moved. Could be
        /// rate-limited by peer availability / distribution.
        case stalledWithPeers = "stalled_with_peers"
        /// Downloaded everything wanted but state is downloading — rare,
        /// typically indicates a pending recheck.
        case awaitingRecheck = "awaiting_recheck"
    }

    public struct Issue: Sendable, Codable, Identifiable {
        public var id: String { infoHash }
        public let infoHash: String
        public let name: String
        public let reason: Reason
        public let firstSeen: Date
        public var lastProgress: Float
        public var lastUpdated: Date
    }

    private struct Progress {
        var value: Float
        var recordedAt: Date
    }

    private let engine: TorrentEngine
    private let store: PersistenceStore
    private let logger: Logger
    private var progressByHash: [String: Progress] = [:]
    private var issuesByHash: [String: Issue] = [:]
    private var reannounced: Set<String> = []

    public init(engine: TorrentEngine, store: PersistenceStore, logger: Logger) {
        self.engine = engine
        self.store = store
        self.logger = logger
    }

    public func snapshot() -> [Issue] {
        Array(issuesByHash.values).sorted { $0.firstSeen < $1.firstSeen }
    }

    public func clearIssue(hash: String) {
        issuesByHash.removeValue(forKey: hash)
        reannounced.remove(hash)
    }

    public func tick(torrents: [TorrentStats]) async {
        let settings = await store.settings()
        let stallSeconds = Double(max(1, settings.healthStallMinutes) * 60)
        let now = Date()

        for torrent in torrents {
            let hash = torrent.infoHash

            // Only evaluate downloading torrents.
            let isDownloading = torrent.state == .downloading
                || torrent.state == .downloadingMetadata
            if !isDownloading || torrent.paused {
                progressByHash.removeValue(forKey: hash)
                issuesByHash.removeValue(forKey: hash)
                continue
            }

            // Track progress; if it moved, reset the stall timer.
            if let last = progressByHash[hash] {
                if torrent.progress > last.value {
                    progressByHash[hash] = Progress(value: torrent.progress, recordedAt: now)
                    if issuesByHash[hash] != nil {
                        // Progress resumed — clear the issue.
                        issuesByHash.removeValue(forKey: hash)
                        reannounced.remove(hash)
                        logger.info("health", "recovered: \(torrent.name)")
                    }
                    continue
                }
                // No progress yet.
                if now.timeIntervalSince(last.recordedAt) < stallSeconds {
                    continue
                }
                let reason = classify(torrent: torrent)
                if var existing = issuesByHash[hash] {
                    existing.lastUpdated = now
                    existing.lastProgress = torrent.progress
                    issuesByHash[hash] = existing
                } else {
                    let issue = Issue(
                        infoHash: hash,
                        name: torrent.name,
                        reason: reason,
                        firstSeen: now,
                        lastProgress: torrent.progress,
                        lastUpdated: now
                    )
                    issuesByHash[hash] = issue
                    logger.warn(
                        "health",
                        "\(torrent.name) stalled (\(reason.rawValue))"
                    )
                    if settings.healthReannounceOnStall, !reannounced.contains(hash) {
                        _ = await engine.reannounce(infoHash: hash)
                        reannounced.insert(hash)
                        logger.info("health", "reannounced \(torrent.name)")
                    }
                }
            } else {
                progressByHash[hash] = Progress(value: torrent.progress, recordedAt: now)
            }
        }

        // Drop stale entries for torrents that no longer exist.
        let liveHashes = Set(torrents.map { $0.infoHash })
        progressByHash = progressByHash.filter { liveHashes.contains($0.key) }
        issuesByHash = issuesByHash.filter { liveHashes.contains($0.key) }
    }

    private func classify(torrent: TorrentStats) -> Reason {
        if torrent.state == .downloadingMetadata {
            return .metadataTimeout
        }
        if torrent.progress >= 0.999 {
            return .awaitingRecheck
        }
        if torrent.numPeers == 0 {
            return .noPeers
        }
        return .stalledWithPeers
    }
}
