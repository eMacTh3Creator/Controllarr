//
//  HTTPServer.swift
//  Controllarr — Phase 1
//
//  Thin wrapper that brings up the Hummingbird app and wires the
//  qBittorrent-compatibility router into it. Expose a single
//  start/stop actor so the SwiftUI shell can own its lifetime.
//

import Foundation
import Hummingbird
import HummingbirdCore
import NIOCore
import TorrentEngine
import Persistence

public actor HTTPServer {

    public struct Configuration: Sendable {
        public var host: String
        public var port: Int
        /// Absolute path to the directory containing the built React WebUI
        /// (index.html + assets/). When nil the server returns a
        /// placeholder page at `/`.
        public var webUIRoot: URL?
        public init(host: String, port: Int, webUIRoot: URL?) {
            self.host = host
            self.port = port
            self.webUIRoot = webUIRoot
        }
    }

    public struct Services: Sendable {
        public let engine: TorrentEngine
        public let store: PersistenceStore
        /// Closure the WebUI exposes as "cycle port now" — implemented by
        /// the PortWatcher. Kept as a closure so HTTPServer doesn't take a
        /// hard dependency on PortWatcher.
        public let forceCyclePort: @Sendable () async -> Void
        public init(
            engine: TorrentEngine,
            store: PersistenceStore,
            forceCyclePort: @escaping @Sendable () async -> Void
        ) {
            self.engine = engine
            self.store = store
            self.forceCyclePort = forceCyclePort
        }
    }

    private let configuration: Configuration
    private let services: Services
    private var runTask: Task<Void, Error>?

    public init(configuration: Configuration, services: Services) {
        self.configuration = configuration
        self.services = services
    }

    public func start() async throws {
        guard runTask == nil else { return }

        let router = Router()
        router.add(middleware: LogRequestsMiddleware())

        // qBittorrent Web API v2 compat surface.
        QBittorrentAPI.install(
            on: router,
            services: services
        )

        // Static WebUI. Registered last so /api/* routes win.
        StaticWebUI.install(on: router, rootDirectory: configuration.webUIRoot)

        let app = Application(
            router: router,
            configuration: .init(
                address: .hostname(configuration.host, port: configuration.port),
                serverName: "Controllarr/0.1"
            )
        )

        let host = configuration.host
        let port = configuration.port
        runTask = Task.detached {
            do {
                NSLog("[Controllarr] HTTP server listening on http://\(host):\(port)")
                try await app.runService()
            } catch {
                NSLog("[Controllarr] HTTP server stopped: \(error)")
                throw error
            }
        }
    }

    public func stop() async {
        runTask?.cancel()
        runTask = nil
    }
}

// MARK: - Middleware

/// Tiny access log. Phase 1 just writes to NSLog — Phase 6 will route the
/// WebUI log viewer through a pubsub on top of this.
struct LogRequestsMiddleware<Context: RequestContext>: RouterMiddleware {
    func handle(
        _ request: Request,
        context: Context,
        next: (Request, Context) async throws -> Response
    ) async throws -> Response {
        let start = Date()
        let response = try await next(request, context)
        let ms = Int(Date().timeIntervalSince(start) * 1000)
        NSLog("[HTTP] \(request.method.rawValue) \(request.uri.path) -> \(response.status.code) (\(ms)ms)")
        return response
    }
}
