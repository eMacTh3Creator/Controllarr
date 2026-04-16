//
//  BandwidthScheduler.swift
//  Controllarr
//
//  Time-of-day bandwidth limiter. Evaluates a list of schedule windows
//  once per minute and applies download/upload rate limits to the
//  libtorrent session. When no window matches, unlimited rates apply.
//

import Foundation
import TorrentEngine
import Persistence

public actor BandwidthScheduler {

    private let engine: TorrentEngine
    private let store: PersistenceStore
    private let logger: Logger
    private var task: Task<Void, Never>?
    private var lastAppliedRuleID: String?

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
                try? await Task.sleep(nanoseconds: 60_000_000_000) // 1 min
            }
        }
    }

    public func stop() {
        task?.cancel()
        task = nil
    }

    /// Force an immediate re-evaluation (e.g. after editing schedule).
    public func forceEvaluate() async {
        await evaluate()
    }

    private func evaluate() async {
        let settings = await store.settings()
        let rules = settings.bandwidthSchedule
        let now = Date()
        let cal = Calendar.current
        let weekday = cal.component(.weekday, from: now) // 1=Sun…7=Sat
        let hour = cal.component(.hour, from: now)
        let minute = cal.component(.minute, from: now)
        let minuteOfDay = hour * 60 + minute

        // Find the first matching window.
        var matched: BandwidthRule? = nil
        for rule in rules where rule.enabled {
            guard rule.daysOfWeek.contains(weekday) else { continue }
            let start = rule.startHour * 60 + rule.startMinute
            let end = rule.endHour * 60 + rule.endMinute
            if start <= end {
                if minuteOfDay >= start && minuteOfDay < end { matched = rule; break }
            } else {
                // Wraps midnight: e.g. 23:00 -> 06:00
                if minuteOfDay >= start || minuteOfDay < end { matched = rule; break }
            }
        }

        let ruleID = matched?.id ?? "__unlimited__"
        guard ruleID != lastAppliedRuleID else { return }
        lastAppliedRuleID = ruleID

        let dlLimit = matched?.maxDownloadKBps ?? 0
        let ulLimit = matched?.maxUploadKBps ?? 0
        await engine.setRateLimits(downloadKBps: dlLimit, uploadKBps: ulLimit)

        if let rule = matched {
            logger.info("scheduler", "bandwidth rule active: ↓\(rule.maxDownloadKBps ?? 0) KiB/s ↑\(rule.maxUploadKBps ?? 0) KiB/s")
        } else {
            logger.info("scheduler", "bandwidth unlimited")
        }
    }
}
