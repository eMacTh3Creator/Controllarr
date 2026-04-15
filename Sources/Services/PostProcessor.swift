//
//  PostProcessor.swift
//  Controllarr
//
//  Post-complete pipeline: when a torrent finishes downloading, the
//  PostProcessor resolves its category, moves the storage to the
//  seeding location if one is configured, and extracts any .rar/.zip
//  archives alongside the moved files.
//
//  Flow (evaluated on every runtime tick, ~2s cadence):
//
//    1. First time a hash reaches progress >= 0.999 -> mark .pending
//    2. .pending      -> decide next step based on its category config
//                        (move? extract? nothing?)
//    3. .movingStorage -> watch savePath via libtorrent until it reflects
//                         the target path, then transition to extracting
//                         or done
//    4. .extracting    -> run bsdtar once per archive detected under the
//                         new savePath, in a detached task so we don't
//                         block the runtime tick. Marks .done on success,
//                         .failed on error.
//
//  No alerts are hooked here — polling state transitions is good enough
//  for Phase 2 and keeps the C++ shim minimal.
//

import Foundation
import TorrentEngine
import Persistence

public actor PostProcessor {

    public enum Stage: Sendable, Equatable {
        case pending
        case movingStorage(targetPath: String, startedAt: Date)
        case extracting
        case done
        case failed(reason: String)
    }

    public struct Record: Sendable, Identifiable {
        public var id: String { infoHash }
        public let infoHash: String
        public let name: String
        public let category: String?
        public var stage: Stage
        public var message: String?
        public var lastUpdated: Date
    }

    private let engine: TorrentEngine
    private let store: PersistenceStore
    private let logger: Logger
    private var records: [String: Record] = [:]

    public init(engine: TorrentEngine, store: PersistenceStore, logger: Logger) {
        self.engine = engine
        self.store = store
        self.logger = logger
    }

    public func snapshot() -> [Record] {
        Array(records.values).sorted { $0.lastUpdated > $1.lastUpdated }
    }

    public func record(for hash: String) -> Record? {
        records[hash]
    }

    /// Advance the state machine for every torrent the engine currently
    /// knows about. Called on the runtime's stats tick.
    public func tick(torrents: [TorrentStats]) async {
        for torrent in torrents {
            await advance(torrent: torrent)
        }
    }

    private func advance(torrent: TorrentStats) async {
        let hash = torrent.infoHash
        let isComplete = torrent.progress >= 0.999
            || torrent.state == .finished
            || torrent.state == .seeding

        // Already tracking something for this hash?
        if var existing = records[hash] {
            switch existing.stage {
            case .done, .failed:
                return
            case .pending:
                await decideNextStep(torrent: torrent, record: &existing)
                records[hash] = existing
            case .movingStorage(let target, let startedAt):
                if torrent.savePath == target {
                    existing.stage = .extracting
                    existing.lastUpdated = Date()
                    records[hash] = existing
                    await extractArchives(in: target, record: existing)
                } else if Date().timeIntervalSince(startedAt) > 600 {
                    // Move has been in flight for 10 minutes — give up.
                    existing.stage = .failed(reason: "move_storage timed out")
                    existing.lastUpdated = Date()
                    records[hash] = existing
                    logger.warn(
                        "post-processor",
                        "move_storage timed out for \(torrent.name)"
                    )
                }
            case .extracting:
                // Handled as a detached task once entered; no polling
                // needed here.
                return
            }
            return
        }

        // Not yet tracked — only enter the pipeline when complete.
        guard isComplete else { return }
        let record = Record(
            infoHash: hash,
            name: torrent.name,
            category: torrent.category,
            stage: .pending,
            message: nil,
            lastUpdated: Date()
        )
        records[hash] = record
        logger.info(
            "post-processor",
            "finished: \(torrent.name) (cat=\(torrent.category ?? "none"))"
        )
        var mutable = record
        await decideNextStep(torrent: torrent, record: &mutable)
        records[hash] = mutable
    }

    private func decideNextStep(torrent: TorrentStats, record: inout Record) async {
        let category: Persistence.Category?
        if let name = torrent.category {
            category = await store.category(named: name)
        } else {
            category = nil
        }

        // No category, or category has nothing to do -> mark done.
        guard let cat = category else {
            record.stage = .done
            record.message = "no category — nothing to do"
            record.lastUpdated = Date()
            return
        }

        // Step 1: move storage if completePath is set and we're not already there.
        if let target = cat.completePath, !target.isEmpty, torrent.savePath != target {
            try? FileManager.default.createDirectory(
                atPath: target,
                withIntermediateDirectories: true
            )
            _ = await engine.move(infoHash: torrent.infoHash, to: URL(fileURLWithPath: target))
            record.stage = .movingStorage(targetPath: target, startedAt: Date())
            record.message = "moving to \(target)"
            record.lastUpdated = Date()
            logger.info("post-processor", "moving \(torrent.name) -> \(target)")
            return
        }

        // Step 2: extract archives if requested.
        if cat.extractArchives {
            record.stage = .extracting
            record.message = "scanning for archives"
            record.lastUpdated = Date()
            await extractArchives(in: torrent.savePath, record: record)
            return
        }

        record.stage = .done
        record.message = "category \(cat.name) — no post actions"
        record.lastUpdated = Date()
    }

    // MARK: Extraction

    private func extractArchives(in directory: String, record: Record) async {
        let hash = record.infoHash
        let name = record.name
        let logger = self.logger
        let root = URL(fileURLWithPath: directory)

        // Snapshot the directory tree once and fan out extractions from
        // a detached task so the actor isn't pinned.
        Task.detached(priority: .utility) { [weak self] in
            let archives = Self.findArchives(under: root)
            if archives.isEmpty {
                await self?.markExtractionDone(hash: hash, message: "no archives found")
                logger.info("post-processor", "\(name): no archives")
                return
            }
            logger.info(
                "post-processor",
                "\(name): extracting \(archives.count) archive\(archives.count == 1 ? "" : "s")"
            )
            for archive in archives {
                let dest = archive.deletingLastPathComponent()
                let result = Self.runBsdtar(archive: archive, destination: dest)
                if !result.success {
                    await self?.markExtractionFailed(
                        hash: hash,
                        reason: "bsdtar \(archive.lastPathComponent): \(result.message)"
                    )
                    logger.warn(
                        "post-processor",
                        "\(name): bsdtar failed on \(archive.lastPathComponent): \(result.message)"
                    )
                    return
                }
                logger.info(
                    "post-processor",
                    "\(name): extracted \(archive.lastPathComponent)"
                )
            }
            await self?.markExtractionDone(hash: hash, message: "extracted \(archives.count)")
        }
    }

    private func markExtractionDone(hash: String, message: String) {
        guard var r = records[hash] else { return }
        r.stage = .done
        r.message = message
        r.lastUpdated = Date()
        records[hash] = r
    }

    private func markExtractionFailed(hash: String, reason: String) {
        guard var r = records[hash] else { return }
        r.stage = .failed(reason: reason)
        r.message = reason
        r.lastUpdated = Date()
        records[hash] = r
    }

    /// Walk `root` and return every file whose extension (case-insensitive)
    /// is one of the supported archive types. Part-1 RARs are preferred —
    /// if we encounter `foo.part2.rar`, `foo.part3.rar`, etc. alongside
    /// `foo.part1.rar`, only the part1 is returned since libarchive drives
    /// the whole set from the first volume.
    static func findArchives(under root: URL) -> [URL] {
        let fm = FileManager.default
        guard let enumerator = fm.enumerator(
            at: root,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsPackageDescendants]
        ) else { return [] }

        var archives: [URL] = []
        for case let url as URL in enumerator {
            guard let rf = try? url.resourceValues(forKeys: [.isRegularFileKey]),
                  rf.isRegularFile == true else { continue }
            let ext = url.pathExtension.lowercased()
            guard ext == "rar" || ext == "zip" || ext == "7z" else { continue }
            if ext == "rar" {
                // Part-N volumes: only accept part1.
                let name = url.deletingPathExtension().lastPathComponent.lowercased()
                if let match = name.range(of: #"\.part(\d+)$"#, options: .regularExpression) {
                    let digits = name[match].dropFirst(5) // skip ".part"
                    if digits != "1" && digits != "01" && digits != "001" { continue }
                }
            }
            archives.append(url)
        }
        return archives.sorted { $0.path < $1.path }
    }

    /// Invoke /usr/bin/bsdtar to extract `archive` into `destination`.
    /// bsdtar is bundled with macOS and handles rar/zip/7z via libarchive.
    static func runBsdtar(archive: URL, destination: URL) -> (success: Bool, message: String) {
        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: "/usr/bin/bsdtar")
        proc.arguments = [
            "-xf", archive.path,
            "-C", destination.path,
        ]
        let errPipe = Pipe()
        proc.standardError = errPipe
        proc.standardOutput = Pipe()
        do {
            try proc.run()
        } catch {
            return (false, "launch failed: \(error.localizedDescription)")
        }
        proc.waitUntilExit()
        if proc.terminationStatus == 0 {
            return (true, "ok")
        }
        let errData = errPipe.fileHandleForReading.readDataToEndOfFile()
        let errMsg = String(data: errData, encoding: .utf8)?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? "exit \(proc.terminationStatus)"
        return (false, errMsg)
    }
}
