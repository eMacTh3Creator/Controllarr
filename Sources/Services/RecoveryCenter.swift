//
//  RecoveryCenter.swift
//  Controllarr
//
//  Rule engine for unhealthy and failed torrents. Watches three sources:
//
//  1. HealthMonitor  — stalled / metadata-timeout / no-peers issues
//  2. PostProcessor  — move and extraction failures
//  3. DiskSpaceMonitor — disk-pressure pause events
//
//  Applies configured recovery rules, supports multiple rules per trigger
//  at different delay thresholds (rule chaining / escalation), and keeps
//  a rolling action log for the UI and API.
//

import Foundation
import TorrentEngine
import Persistence

public actor RecoveryCenter {

    public enum Source: String, Sendable, Codable {
        case automatic
        case manual
    }

    /// Unified issue representation. Health issues come from HealthMonitor,
    /// post-processing issues are synthesised from PostProcessor.Record,
    /// disk-pressure issues from DiskSpaceMonitor.
    public struct Issue: Sendable {
        public let infoHash: String
        public let name: String
        public let trigger: RecoveryTrigger
        public let firstSeen: Date
    }

    public struct Record: Sendable, Codable, Identifiable {
        public var id: String { "\(infoHash)-\(timestamp.timeIntervalSince1970)-\(source.rawValue)" }
        public let infoHash: String
        public let name: String
        public let reason: RecoveryTrigger
        public let action: RecoveryAction
        public let source: Source
        public let success: Bool
        public let message: String
        public let timestamp: Date
    }

    public struct PlannedAction: Sendable, Equatable {
        public let infoHash: String
        public let name: String
        public let reason: RecoveryTrigger
        public let action: RecoveryAction
        public let signature: String
    }

    public enum Error: Swift.Error, LocalizedError {
        case issueNotFound(String)

        public var errorDescription: String? {
            switch self {
            case .issueNotFound(let hash):
                return "No active issue found for \(hash)."
            }
        }
    }

    private let engine: TorrentEngine
    private let store: PersistenceStore
    private let healthMonitor: HealthMonitor
    private let postProcessor: PostProcessor
    private let diskSpaceMonitor: DiskSpaceMonitor
    private let logger: Logger

    /// issue hash -> automatic rule signatures already applied while the
    /// issue remains active. Cleared once the issue disappears.
    private var appliedAutomaticRules: [String: Set<String>] = [:]

    /// Tracks when we first observed each post-processing or disk-pressure
    /// issue so we can apply delay thresholds correctly. Health issues
    /// carry their own firstSeen from HealthMonitor.
    private var issueFirstSeen: [String: Date] = [:]

    private var recent: [Record] = []
    private static let maxRecords = 200

    public init(
        engine: TorrentEngine,
        store: PersistenceStore,
        healthMonitor: HealthMonitor,
        postProcessor: PostProcessor,
        diskSpaceMonitor: DiskSpaceMonitor,
        logger: Logger
    ) {
        self.engine = engine
        self.store = store
        self.healthMonitor = healthMonitor
        self.postProcessor = postProcessor
        self.diskSpaceMonitor = diskSpaceMonitor
        self.logger = logger
    }

    public func snapshot() -> [Record] {
        recent.sorted { $0.timestamp > $1.timestamp }
    }

    // MARK: - Tick (automatic)

    public func tick(torrents: [TorrentStats]) async {
        let settings = await store.settings()
        let now = Date()

        // Gather unified issue list from all three sources.
        let allIssues = await gatherIssues(at: now, torrents: torrents)
        let liveHashes = Set(allIssues.map(\.infoHash))

        // Purge applied-rules for issues that no longer exist.
        appliedAutomaticRules = appliedAutomaticRules.filter { liveHashes.contains($0.key) }
        issueFirstSeen = issueFirstSeen.filter { liveHashes.contains($0.key) }

        let plans = Self.plan(
            issues: allIssues,
            rules: settings.recoveryRules,
            at: now,
            appliedAutomaticRules: appliedAutomaticRules
        )

        for plan in plans {
            let record = await execute(
                infoHash: plan.infoHash,
                name: plan.name,
                reason: plan.reason,
                action: plan.action,
                source: .automatic,
                context: "automatic rule match"
            )
            appliedAutomaticRules[plan.infoHash, default: []].insert(plan.signature)
            append(record)
        }
    }

    // MARK: - Manual recovery

    public func runRecovery(for hash: String, action overrideAction: RecoveryAction? = nil) async throws -> Record {
        let allIssues = await gatherIssues(at: Date(), torrents: nil)
        guard let issue = allIssues.first(where: { $0.infoHash == hash }) else {
            throw Error.issueNotFound(hash)
        }

        let settings = await store.settings()
        let configuredRule = settings.recoveryRules.first {
            $0.enabled && $0.trigger == issue.trigger
        }
        let action = overrideAction ?? configuredRule?.action ?? .reannounce
        let context: String
        if overrideAction != nil {
            context = "manual override"
        } else if configuredRule != nil {
            context = "manual run using configured rule"
        } else {
            context = "manual fallback reannounce"
        }

        let record = await execute(
            infoHash: issue.infoHash,
            name: issue.name,
            reason: issue.trigger,
            action: action,
            source: .manual,
            context: context
        )
        append(record)
        return record
    }

    // MARK: - Issue gathering

    private func gatherIssues(at now: Date, torrents: [TorrentStats]?) async -> [Issue] {
        var issues: [Issue] = []

        // 1. Health monitor issues
        let healthIssues = await healthMonitor.snapshot()
        for h in healthIssues {
            if let trigger = RecoveryTrigger(rawValue: h.reason.rawValue) {
                issues.append(Issue(
                    infoHash: h.infoHash,
                    name: h.name,
                    trigger: trigger,
                    firstSeen: h.firstSeen
                ))
            }
        }

        // 2. Post-processor failures
        let postRecords = await postProcessor.snapshot()
        for r in postRecords {
            let trigger: RecoveryTrigger?
            switch r.stage {
            case .failed(let reason):
                if reason.contains("move_storage") {
                    trigger = .postProcessMoveFailed
                } else {
                    trigger = .postProcessExtractionFailed
                }
            default:
                trigger = nil
            }
            if let trigger {
                let key = "\(r.infoHash)-\(trigger.rawValue)"
                let firstSeen = issueFirstSeen[key] ?? now
                if issueFirstSeen[key] == nil {
                    issueFirstSeen[key] = firstSeen
                }
                issues.append(Issue(
                    infoHash: r.infoHash,
                    name: r.name,
                    trigger: trigger,
                    firstSeen: firstSeen
                ))
            }
        }

        // 3. Disk pressure — creates an issue for each torrent paused by
        //    the disk-space monitor so rules can escalate per-torrent.
        let dsStatus = await diskSpaceMonitor.snapshot()
        if dsStatus.isPaused {
            let torrentLookup: [String: TorrentStats]
            if let torrents {
                torrentLookup = Dictionary(uniqueKeysWithValues: torrents.map { ($0.infoHash, $0) })
            } else {
                let loaded = await engine.pollStats()
                torrentLookup = Dictionary(uniqueKeysWithValues: loaded.map { ($0.infoHash, $0) })
            }
            for hash in dsStatus.pausedHashes {
                let name = torrentLookup[hash]?.name ?? hash
                let key = "\(hash)-\(RecoveryTrigger.diskPressure.rawValue)"
                let firstSeen = issueFirstSeen[key] ?? now
                if issueFirstSeen[key] == nil {
                    issueFirstSeen[key] = firstSeen
                }
                issues.append(Issue(
                    infoHash: hash,
                    name: name,
                    trigger: .diskPressure,
                    firstSeen: firstSeen
                ))
            }
        }

        return issues
    }

    // MARK: - Planner (supports rule chaining)

    /// Returns every action that should fire right now. Multiple rules per
    /// trigger at different delay thresholds are supported — each fires
    /// independently when its delay elapses and its unique signature hasn't
    /// been applied yet.
    static func plan(
        issues: [Issue],
        rules: [RecoveryRule],
        at now: Date,
        appliedAutomaticRules: [String: Set<String>]
    ) -> [PlannedAction] {
        var actions: [PlannedAction] = []
        for issue in issues {
            // Collect ALL enabled rules that match this trigger (not just first).
            let matching = rules.filter { $0.enabled && $0.trigger == issue.trigger }
            for rule in matching {
                let delaySeconds = Double(max(0, rule.delayMinutes) * 60)
                guard now.timeIntervalSince(issue.firstSeen) >= delaySeconds else {
                    continue
                }
                let signature = Self.signature(for: rule)
                guard appliedAutomaticRules[issue.infoHash]?.contains(signature) != true else {
                    continue
                }
                actions.append(PlannedAction(
                    infoHash: issue.infoHash,
                    name: issue.name,
                    reason: issue.trigger,
                    action: rule.action,
                    signature: signature
                ))
            }
        }
        return actions
    }

    // MARK: - Execution

    private func execute(
        infoHash: String,
        name: String,
        reason: RecoveryTrigger,
        action: RecoveryAction,
        source: Source,
        context: String
    ) async -> Record {
        let success: Bool
        switch action {
        case .reannounce:
            success = await engine.reannounce(infoHash: infoHash)
        case .pause:
            success = await engine.pause(infoHash: infoHash)
        case .removeKeepFiles:
            success = await engine.remove(infoHash: infoHash, deleteFiles: false)
        case .removeDeleteFiles:
            success = await engine.remove(infoHash: infoHash, deleteFiles: true)
        case .retryPostProcess:
            do {
                _ = try await postProcessor.retry(infoHash: infoHash)
                success = true
            } catch {
                logger.warn("recovery", "retry post-process failed for \(name): \(error.localizedDescription)")
                success = false
            }
        }

        let message = success
            ? "\(context): \(action.rawValue)"
            : "\(context): engine refused \(action.rawValue)"

        if success {
            logger.info("recovery", "\(source.rawValue) \(action.rawValue): \(name) [\(reason.rawValue)]")
        } else {
            logger.warn("recovery", "\(source.rawValue) \(action.rawValue) failed: \(name) [\(reason.rawValue)]")
        }

        return Record(
            infoHash: infoHash,
            name: name,
            reason: reason,
            action: action,
            source: source,
            success: success,
            message: message,
            timestamp: Date()
        )
    }

    private func append(_ record: Record) {
        recent.append(record)
        if recent.count > Self.maxRecords {
            recent.removeFirst(recent.count - Self.maxRecords)
        }
    }

    private static func signature(for rule: RecoveryRule) -> String {
        "\(rule.trigger.rawValue)|\(rule.action.rawValue)|\(max(0, rule.delayMinutes))"
    }
}
