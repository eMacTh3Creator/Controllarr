//
//  ControllarrCore.swift
//  Controllarr
//
//  Wires every service actor — engine, persistence, port watcher, HTTP
//  server, logger, post-processor, seeding policy, health monitor,
//  bandwidth scheduler — into one boot/shutdown surface. The SwiftUI app
//  target uses this as its entry point: pass in the WebUI resource
//  directory, call start(), and you have a running Controllarr.
//

import Foundation
import TorrentEngine
import Persistence
import PortWatcher
import Services
import HTTPServer

public actor ControllarrRuntime {

    public nonisolated let store: PersistenceStore
    public nonisolated let engine: TorrentEngine
    public nonisolated let portWatcher: PortWatcher
    public nonisolated let httpServer: HTTPServer
    public nonisolated let logger: Logger
    public nonisolated let postProcessor: PostProcessor
    public nonisolated let seedingPolicy: SeedingPolicy
    public nonisolated let healthMonitor: HealthMonitor
    public nonisolated let bandwidthScheduler: BandwidthScheduler

    private var tickTask: Task<Void, Never>?

    public init(webUIRoot: URL?) async {
        let logger = Logger()
        self.logger = logger

        let store = PersistenceStore()
        self.store = store

        let snapshot = await store.snapshot()
        let savePathURL = URL(fileURLWithPath: snapshot.settings.defaultSavePath)
        let listenPort  = snapshot.lastKnownGoodPort ?? snapshot.settings.listenPortRangeStart

        let engine = TorrentEngine(
            defaultSavePath: savePathURL,
            resumeDataDirectory: store.resumeDir,
            listenPort: listenPort,
            resolver: { category in
                await store.savePath(forCategory: category)
            }
        )
        self.engine = engine
        await engine.restoreCategories(snapshot.categoryByHash)

        // Seed the engine's blocked-extension cache from persisted
        // categories so filtering applies on restart.
        for category in snapshot.categories {
            await engine.registerBlockedExtensions(
                category.blockedExtensions,
                forCategory: category.name
            )
        }

        let portWatcher = PortWatcher(engine: engine, store: store)
        self.portWatcher = portWatcher

        let postProcessor = PostProcessor(engine: engine, store: store, logger: logger)
        self.postProcessor = postProcessor

        let seedingPolicy = SeedingPolicy(engine: engine, store: store, logger: logger)
        self.seedingPolicy = seedingPolicy

        let healthMonitor = HealthMonitor(engine: engine, store: store, logger: logger)
        self.healthMonitor = healthMonitor

        let bandwidthScheduler = BandwidthScheduler(engine: engine, store: store, logger: logger)
        self.bandwidthScheduler = bandwidthScheduler

        let httpConfig = HTTPServer.Configuration(
            host: snapshot.settings.webUIHost,
            port: snapshot.settings.webUIPort,
            webUIRoot: webUIRoot
        )
        let services = HTTPServer.Services(
            engine: engine,
            store: store,
            logger: logger,
            postProcessor: postProcessor,
            seedingPolicy: seedingPolicy,
            healthMonitor: healthMonitor,
            forceCyclePort: { [weak portWatcher] in
                await portWatcher?.forceCycle(reason: "manual via /api/controllarr/port/cycle")
            }
        )
        self.httpServer = HTTPServer(configuration: httpConfig, services: services)
    }

    public func start() async throws {
        await portWatcher.start()
        await bandwidthScheduler.start()
        try await httpServer.start()
        startTickLoop()
        logger.info("runtime", "Controllarr runtime started")
    }

    public func shutdown() async {
        logger.info("runtime", "Controllarr runtime shutting down")
        tickTask?.cancel()
        tickTask = nil
        await portWatcher.stop()
        await bandwidthScheduler.stop()
        await httpServer.stop()
        let categories = await engine.snapshotCategories()
        await store.setCategoryMap(categories)
        let port = await engine.listenPort
        await store.setLastKnownGoodPort(port)
        await store.flushNow()
        await engine.shutdown()
    }

    /// Background task that polls TorrentEngine ~every 2s and fans the
    /// snapshot out to every stateful service.
    private func startTickLoop() {
        tickTask?.cancel()
        let engine = self.engine
        let postProcessor = self.postProcessor
        let seedingPolicy = self.seedingPolicy
        let healthMonitor = self.healthMonitor
        tickTask = Task.detached(priority: .utility) {
            while !Task.isCancelled {
                await engine.applyPendingFileFilters()
                let torrents = await engine.pollStats()
                await postProcessor.tick(torrents: torrents)
                await seedingPolicy.tick(torrents: torrents)
                await healthMonitor.tick(torrents: torrents)
                try? await Task.sleep(nanoseconds: 2_000_000_000)
            }
        }
    }
}
