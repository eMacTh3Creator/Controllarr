//
//  ControllarrCore.swift
//  Controllarr — Phase 1
//
//  Wires the engine, persistence, port watcher, and HTTP server into one
//  boot/shutdown surface. The SwiftUI app target uses this as its entry
//  point — pass in the WebUI resource directory, call start(), and you
//  have a running Controllarr.
//

import Foundation
import TorrentEngine
import Persistence
import PortWatcher
import HTTPServer

public actor ControllarrRuntime {

    public let store: PersistenceStore
    public let engine: TorrentEngine
    public let portWatcher: PortWatcher
    public let httpServer: HTTPServer

    public init(webUIRoot: URL?) async {
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

        let portWatcher = PortWatcher(engine: engine, store: store)
        self.portWatcher = portWatcher

        let httpConfig = HTTPServer.Configuration(
            host: snapshot.settings.webUIHost,
            port: snapshot.settings.webUIPort,
            webUIRoot: webUIRoot
        )
        let services = HTTPServer.Services(
            engine: engine,
            store: store,
            forceCyclePort: { [weak portWatcher] in
                await portWatcher?.forceCycle(reason: "manual via /api/controllarr/port/cycle")
            }
        )
        self.httpServer = HTTPServer(configuration: httpConfig, services: services)
    }

    public func start() async throws {
        await portWatcher.start()
        try await httpServer.start()
        NSLog("[Controllarr] runtime started")
    }

    public func shutdown() async {
        NSLog("[Controllarr] runtime shutting down")
        await portWatcher.stop()
        await httpServer.stop()
        let categories = await engine.snapshotCategories()
        await store.setCategoryMap(categories)
        let port = await engine.listenPort
        await store.setLastKnownGoodPort(port)
        await store.flushNow()
        await engine.shutdown()
    }
}
