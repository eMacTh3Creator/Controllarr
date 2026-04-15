//
//  SeedingPolicy.swift
//  Controllarr
//
//  Enforces share ratio and seeding-time limits. Runs on every runtime
//  tick, never removes a torrent that hasn't met the minimum seed-time
//  threshold (hit-and-run protection), and takes the action configured
//  in Settings (pause / remove keeping files / remove deleting files).
//

import Foundation
import TorrentEngine
import Persistence

public actor SeedingPolicy {

    public struct Enforcement: Sendable, Identifiable {
        public var id: String { "\(infoHash)-\(timestamp.timeIntervalSince1970)" }
        public let infoHash: String
        public let name: String
        public let reason: String
        public let action: SeedLimitAction
        public let timestamp: Date
    }

    private let engine: TorrentEngine
    private let store: PersistenceStore
    private let logger: Logger
    /// Hash -> epoch seconds first seen as seeding. Tracked in memory
    /// because the runtime already survives across process restarts via
    /// the libtorrent resume-data file, which preserves all-time ratio
    /// and total upload — the only state we actually need here.
    private var seedingSince: [String: Date] = [:]
    /// Hashes we've already acted on — don't double-pause.
    private var actedOn: Set<String> = []
    /// Rolling log of enforcement decisions, for the UI.
    private var recent: [Enforcement] = []

    public init(engine: TorrentEngine, store: PersistenceStore, logger: Logger) {
        self.engine = engine
        self.store = store
        self.logger = logger
    }

    public func snapshot() -> [Enforcement] {
        recent.sorted { $0.timestamp > $1.timestamp }
    }

    public func tick(torrents: [TorrentStats]) async {
        let settings = await store.settings()

        for torrent in torrents {
            let hash = torrent.infoHash
            let isSeeding = torrent.state == .seeding
                || torrent.state == .finished
                || (torrent.progress >= 0.999 && !torrent.paused)

            if !isSeeding {
                seedingSince.removeValue(forKey: hash)
                continue
            }
            if seedingSince[hash] == nil {
                seedingSince[hash] = Date()
            }

            if actedOn.contains(hash) { continue }

            // Resolve per-category overrides.
            var effectiveMaxRatio = settings.globalMaxRatio
            var effectiveMaxMinutes = settings.globalMaxSeedingTimeMinutes
            if let categoryName = torrent.category,
               let category = await store.category(named: categoryName) {
                if let v = category.maxRatio { effectiveMaxRatio = v }
                if let v = category.maxSeedingTimeMinutes { effectiveMaxMinutes = v }
            }

            // Check minimum seed time (hit-and-run protection) first —
            // never remove under this threshold even if ratio is huge.
            let seedElapsed = Date().timeIntervalSince(seedingSince[hash]!)
            let minSeedSeconds = Double(settings.minimumSeedTimeMinutes * 60)

            var reason: String?
            if let maxRatio = effectiveMaxRatio, maxRatio > 0, torrent.ratio >= maxRatio {
                reason = String(format: "ratio %.2f >= %.2f", torrent.ratio, maxRatio)
            } else if let maxMinutes = effectiveMaxMinutes, maxMinutes > 0 {
                let elapsedMinutes = Int(seedElapsed / 60)
                if elapsedMinutes >= maxMinutes {
                    reason = "seeded \(elapsedMinutes)m >= \(maxMinutes)m"
                }
            }

            guard let reason else { continue }

            // Hit-and-run guard: if the torrent hasn't met the minimum
            // seed time, clamp the action to pause-only regardless of
            // configured policy, to preserve tracker standing.
            let action: SeedLimitAction
            if seedElapsed < minSeedSeconds {
                action = .pause
            } else {
                action = settings.seedLimitAction
            }

            await apply(action: action, torrent: torrent, reason: reason)
            actedOn.insert(hash)
        }
    }

    private func apply(action: SeedLimitAction, torrent: TorrentStats, reason: String) async {
        switch action {
        case .pause:
            _ = await engine.pause(infoHash: torrent.infoHash)
        case .removeKeepFiles:
            _ = await engine.remove(infoHash: torrent.infoHash, deleteFiles: false)
        case .removeDeleteFiles:
            _ = await engine.remove(infoHash: torrent.infoHash, deleteFiles: true)
        }
        let enforcement = Enforcement(
            infoHash: torrent.infoHash,
            name: torrent.name,
            reason: reason,
            action: action,
            timestamp: Date()
        )
        recent.append(enforcement)
        if recent.count > 100 { recent.removeFirst(recent.count - 100) }
        logger.info(
            "seeding-policy",
            "\(action.rawValue): \(torrent.name) (\(reason))"
        )
    }
}
