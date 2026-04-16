//
//  ControllarrCore.swift
//  Controllarr
//
//  Wires every service actor — engine, persistence, port watcher, HTTP
//  server, logger, post-processor, seeding policy, health monitor,
//  bandwidth scheduler, disk space monitor, *arr notifier — into one
//  boot/shutdown surface. The SwiftUI app
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
    public nonisolated let recoveryCenter: RecoveryCenter
    public nonisolated let bandwidthScheduler: BandwidthScheduler
    public nonisolated let diskSpaceMonitor: DiskSpaceMonitor
    public nonisolated let vpnMonitor: VPNMonitor
    public nonisolated let arrNotifier: ArrNotifier

    private var tickTask: Task<Void, Never>?

    public init(
        webUIRoot: URL?,
        storeDirectory: URL? = nil,
        httpHostOverride: String? = nil,
        httpPortOverride: Int? = nil
    ) async {
        let logger = Logger()
        self.logger = logger

        let store = PersistenceStore(directory: storeDirectory ?? PersistenceStore.defaultDirectory())
        self.store = store
        await store.flushMigrationIfNeeded()

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

        let diskSpaceMonitor = DiskSpaceMonitor(engine: engine, store: store, logger: logger)
        self.diskSpaceMonitor = diskSpaceMonitor

        let recoveryCenter = RecoveryCenter(
            engine: engine,
            store: store,
            healthMonitor: healthMonitor,
            postProcessor: postProcessor,
            diskSpaceMonitor: diskSpaceMonitor,
            logger: logger
        )
        self.recoveryCenter = recoveryCenter

        let vpnMonitor = VPNMonitor(engine: engine, store: store, logger: logger)
        self.vpnMonitor = vpnMonitor

        let arrNotifier = ArrNotifier(engine: engine, store: store, healthMonitor: healthMonitor, logger: logger)
        self.arrNotifier = arrNotifier

        let httpConfig = HTTPServer.Configuration(
            host: httpHostOverride ?? snapshot.settings.webUIHost,
            port: httpPortOverride ?? snapshot.settings.webUIPort,
            webUIRoot: webUIRoot
        )
        let services = HTTPServer.Services(
            engine: engine,
            store: store,
            logger: logger,
            postProcessor: postProcessor,
            seedingPolicy: seedingPolicy,
            healthMonitor: healthMonitor,
            recoveryCenter: recoveryCenter,
            diskSpaceMonitor: diskSpaceMonitor,
            vpnMonitor: vpnMonitor,
            arrNotifier: arrNotifier,
            forceCyclePort: { [weak portWatcher] in
                await portWatcher?.forceCycle(reason: "manual via /api/controllarr/port/cycle")
            }
        )
        self.httpServer = HTTPServer(configuration: httpConfig, services: services)
    }

    public func start() async throws {
        await applyNetworkSettings()
        await portWatcher.start()
        await bandwidthScheduler.start()
        await diskSpaceMonitor.start()
        await vpnMonitor.start()
        try await httpServer.start()
        startTickLoop()
        logger.info("runtime", "Controllarr runtime started")
    }

    /// Push the persisted peer-discovery + connection-limit settings into
    /// libtorrent. Safe to call repeatedly — used on boot and whenever the
    /// operator saves the settings form.
    public func applyNetworkSettings() async {
        let settings = await store.settings()
        await engine.setPeerDiscovery(
            dht: settings.peerDiscovery.dhtEnabled,
            pex: settings.peerDiscovery.pexEnabled,
            lsd: settings.peerDiscovery.lsdEnabled
        )
        await engine.setConnectionLimits(
            globalConnections: settings.connectionLimits.globalMaxConnections,
            perTorrentConnections: settings.connectionLimits.maxConnectionsPerTorrent,
            globalUploads: settings.connectionLimits.globalMaxUploads,
            perTorrentUploads: settings.connectionLimits.maxUploadsPerTorrent
        )
    }

    public func shutdown() async {
        logger.info("runtime", "Controllarr runtime shutting down")
        tickTask?.cancel()
        tickTask = nil
        await portWatcher.stop()
        await bandwidthScheduler.stop()
        await diskSpaceMonitor.stop()
        await vpnMonitor.stop()
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
    ///
    /// Every ~30s the loop also asks the engine to serialize resume data
    /// so that an unclean shutdown (force-quit, crash, power loss) won't
    /// leave the torrent list empty on next launch.
    private func startTickLoop() {
        tickTask?.cancel()
        let engine = self.engine
        let postProcessor = self.postProcessor
        let seedingPolicy = self.seedingPolicy
        let healthMonitor = self.healthMonitor
        let recoveryCenter = self.recoveryCenter
        let arrNotifier = self.arrNotifier
        tickTask = Task.detached(priority: .utility) {
            var tickCount: UInt = 0
            let resumeSaveEveryNTicks: UInt = 15 // ~30s at a 2s cadence.
            while !Task.isCancelled {
                await engine.applyPendingFileFilters()
                let torrents = await engine.pollStats()
                async let postTick: Void = postProcessor.tick(torrents: torrents)
                async let seedingTick: Void = seedingPolicy.tick(torrents: torrents)
                async let healthTick: Void = healthMonitor.tick(torrents: torrents)
                _ = await (postTick, seedingTick, healthTick)

                async let recoveryTick: Void = recoveryCenter.tick(torrents: torrents)
                async let arrTick: Void = arrNotifier.tick(torrents: torrents)
                _ = await (recoveryTick, arrTick)

                tickCount &+= 1
                if tickCount % resumeSaveEveryNTicks == 0 {
                    await engine.saveResumeData()
                }
                try? await Task.sleep(nanoseconds: 2_000_000_000)
            }
        }
    }
}
