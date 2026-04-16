//
//  DiskSpaceMonitor.swift
//  Controllarr
//
//  Periodically checks available disk space on the volume containing the
//  default save path (or a user-configured monitor path). When free space
//  drops below the configured minimum, all actively-downloading torrents
//  are paused. When space is freed, they are automatically resumed.
//

import Foundation
import TorrentEngine
import Persistence

public actor DiskSpaceMonitor {

    public struct Status: Sendable {
        /// Free disk space in bytes on the monitored volume.
        public let freeBytes: Int64
        /// The configured minimum threshold in bytes.
        public let thresholdBytes: Int64
        /// True if downloads are currently paused due to low space.
        public let isPaused: Bool
        /// Hashes of torrents paused by the disk space monitor.
        public let pausedHashes: Set<String>
    }

    private let engine: TorrentEngine
    private let store: PersistenceStore
    private let logger: Logger
    private var task: Task<Void, Never>?

    /// Hashes that **we** paused. Only these get auto-resumed when space
    /// is freed; user-paused torrents are left alone.
    private var pausedByUs: Set<String> = []
    private var lastFreeBytes: Int64 = 0
    private var downloadsPaused: Bool = false

    public init(engine: TorrentEngine, store: PersistenceStore, logger: Logger) {
        self.engine = engine
        self.store = store
        self.logger = logger
    }

    public func start() {
        task?.cancel()
        task = Task { [weak self] in
            while !Task.isCancelled {
                await self?.evaluate()
                try? await Task.sleep(nanoseconds: 30_000_000_000) // 30s
            }
        }
    }

    public func stop() {
        task?.cancel()
        task = nil
    }

    public func snapshot() -> Status {
        let settings = Status(
            freeBytes: lastFreeBytes,
            thresholdBytes: 0,
            isPaused: downloadsPaused,
            pausedHashes: pausedByUs
        )
        return settings
    }

    /// Force an immediate re-evaluation (e.g. after editing settings).
    public func forceEvaluate() async {
        await evaluate()
    }

    private func evaluate() async {
        let settings = await store.settings()

        // Feature disabled?
        guard let minGB = settings.diskSpaceMinimumGB, minGB > 0 else {
            // If we previously paused torrents and the feature was disabled,
            // resume them.
            if downloadsPaused {
                await resumeAll()
                downloadsPaused = false
                logger.info("diskspace", "monitor disabled — resumed paused torrents")
            }
            return
        }

        let monitorPath: String
        if settings.diskSpaceMonitorPath.isEmpty {
            monitorPath = settings.defaultSavePath
        } else {
            monitorPath = settings.diskSpaceMonitorPath
        }

        guard let freeBytes = freeDiskSpace(at: monitorPath) else {
            logger.warn("diskspace", "could not read free space at \(monitorPath)")
            return
        }

        lastFreeBytes = freeBytes
        let thresholdBytes = Int64(minGB) * 1_073_741_824 // GB -> bytes

        if freeBytes < thresholdBytes {
            // Low space — pause all downloading torrents.
            if !downloadsPaused {
                let torrents = await engine.pollStats()
                var count = 0
                for t in torrents {
                    let isDownloading = (t.state == .downloading || t.state == .downloadingMetadata) && !t.paused
                    if isDownloading {
                        _ = await engine.pause(infoHash: t.infoHash)
                        pausedByUs.insert(t.infoHash)
                        count += 1
                    }
                }
                downloadsPaused = true
                let freeGB = String(format: "%.1f", Double(freeBytes) / 1_073_741_824)
                logger.warn("diskspace", "low disk space (\(freeGB) GB free < \(minGB) GB min) — paused \(count) downloading torrents")
            }
        } else if downloadsPaused {
            // Space recovered — resume what we paused.
            await resumeAll()
            downloadsPaused = false
            let freeGB = String(format: "%.1f", Double(freeBytes) / 1_073_741_824)
            logger.info("diskspace", "disk space recovered (\(freeGB) GB free) — resumed torrents")
        }
    }

    private func resumeAll() async {
        for hash in pausedByUs {
            _ = await engine.resume(infoHash: hash)
        }
        pausedByUs.removeAll()
    }

    private func freeDiskSpace(at path: String) -> Int64? {
        do {
            let attrs = try FileManager.default.attributesOfFileSystem(forPath: path)
            if let free = attrs[.systemFreeSize] as? Int64 {
                return free
            }
            if let free = attrs[.systemFreeSize] as? NSNumber {
                return free.int64Value
            }
            return nil
        } catch {
            return nil
        }
    }
}
