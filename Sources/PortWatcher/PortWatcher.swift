//
//  PortWatcher.swift
//  Controllarr — Phase 1
//
//  The #1 reason this project exists. Detects "my listen port went dark,
//  all my torrents are stalled" and automatically cycles to a new port
//  from a configurable pool, re-announces to trackers, and remembers
//  which ports have been burned so we don't cycle back.
//
//  Stall detection is deliberately simple in Phase 1: if we have any
//  active (non-paused, non-seeding-only) torrents and session-wide
//  payload_download_rate has been zero for `stallThresholdMinutes`, the
//  port is considered dead. Phase 2 will augment this with an explicit
//  external reachability probe.
//

import Foundation
import TorrentEngine
import Persistence

public actor PortWatcher {

    public enum Event: Sendable {
        case healthy(port: UInt16)
        case stallDetected(port: UInt16, sinceSeconds: Int)
        case portSwitched(from: UInt16, to: UInt16, reason: String)
    }

    private let engine: TorrentEngine
    private let store: PersistenceStore
    private let pollInterval: TimeInterval
    private var task: Task<Void, Never>?
    private var burned: Set<UInt16> = []
    private var stalledSince: Date?
    private var eventHandler: (@Sendable (Event) -> Void)?

    public init(
        engine: TorrentEngine,
        store: PersistenceStore,
        pollInterval: TimeInterval = 30
    ) {
        self.engine = engine
        self.store = store
        self.pollInterval = pollInterval
    }

    public func onEvent(_ handler: @escaping @Sendable (Event) -> Void) {
        self.eventHandler = handler
    }

    public func start() {
        guard task == nil else { return }
        task = Task { [weak self] in
            await self?.loop()
        }
    }

    public func stop() {
        task?.cancel()
        task = nil
    }

    // MARK: - Loop

    private func loop() async {
        while !Task.isCancelled {
            await tick()
            try? await Task.sleep(nanoseconds: UInt64(pollInterval * 1_000_000_000))
        }
    }

    private func tick() async {
        let session = await engine.sessionStats()
        let torrents = await engine.pollStats()
        let settings = await store.settings()
        let threshold = TimeInterval(max(1, settings.stallThresholdMinutes) * 60)

        // Only evaluate stall if there are torrents actually trying to
        // download (have work to do, aren't paused, aren't already fully
        // done). If everything is seeding or paused, lack of download
        // rate is expected.
        let hasActive = torrents.contains { t in
            !t.paused
            && t.state != .seeding
            && t.state != .finished
            && t.totalWanted > t.totalDone
        }

        guard hasActive else {
            // Nothing to watch; reset any pending stall timer.
            stalledSince = nil
            eventHandler?(.healthy(port: session.listenPort))
            return
        }

        if session.downloadRate == 0 {
            if stalledSince == nil { stalledSince = Date() }
            let elapsed = Date().timeIntervalSince(stalledSince ?? Date())
            if elapsed >= threshold {
                await reselectPort(
                    currentPort: session.listenPort,
                    settings: settings,
                    reason: "no payload download for \(Int(elapsed))s with \(torrents.count) active torrent(s)"
                )
            } else {
                eventHandler?(.stallDetected(port: session.listenPort, sinceSeconds: Int(elapsed)))
            }
        } else {
            stalledSince = nil
            eventHandler?(.healthy(port: session.listenPort))
        }
    }

    // MARK: - Port selection

    private func reselectPort(
        currentPort: UInt16,
        settings: Settings,
        reason: String
    ) async {
        // Burn the current port and pick a fresh one. Burned ports are
        // forgotten after the burn list reaches half the pool size —
        // otherwise a long-running process eventually runs out.
        burned.insert(currentPort)
        let poolSize = Int(settings.listenPortRangeEnd) - Int(settings.listenPortRangeStart) + 1
        if burned.count > max(4, poolSize / 2) {
            burned = [currentPort]
        }

        guard let newPort = pickPort(settings: settings) else {
            NSLog("[Controllarr] PortWatcher: no free port available in range")
            return
        }

        await engine.setListenPort(newPort)
        await engine.forceReannounceAll()
        await store.setLastKnownGoodPort(newPort)

        stalledSince = nil
        eventHandler?(.portSwitched(from: currentPort, to: newPort, reason: reason))
        NSLog("[Controllarr] PortWatcher: cycled \(currentPort) -> \(newPort) (\(reason))")
    }

    private func pickPort(settings: Settings) -> UInt16? {
        let lo = Int(settings.listenPortRangeStart)
        let hi = Int(settings.listenPortRangeEnd)
        guard hi >= lo else { return nil }
        // Random sampling with retry; deterministic enough for our needs
        // and avoids the complexity of a shuffled iterator in an actor.
        for _ in 0..<64 {
            let p = UInt16.random(in: UInt16(lo)...UInt16(hi))
            if !burned.contains(p) { return p }
        }
        // Fallback: first non-burned port in range.
        for p in lo...hi where !burned.contains(UInt16(p)) {
            return UInt16(p)
        }
        return nil
    }

    // MARK: - Test / UI hook

    /// Manually force a port cycle. Used by the "Cycle Port Now" button
    /// in the WebUI.
    public func forceCycle(reason: String = "manual") async {
        let session = await engine.sessionStats()
        let settings = await store.settings()
        await reselectPort(currentPort: session.listenPort, settings: settings, reason: reason)
    }
}
