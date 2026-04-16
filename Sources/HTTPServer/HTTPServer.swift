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
import Services

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
        public let logger: Logger
        public let postProcessor: PostProcessor
        public let seedingPolicy: SeedingPolicy
        public let healthMonitor: HealthMonitor
        public let recoveryCenter: RecoveryCenter
        public let diskSpaceMonitor: DiskSpaceMonitor
        public let vpnMonitor: VPNMonitor
        public let arrNotifier: ArrNotifier
        /// Closure the WebUI exposes as "cycle port now" — implemented by
        /// the PortWatcher. Kept as a closure so HTTPServer doesn't take a
        /// hard dependency on PortWatcher.
        public let forceCyclePort: @Sendable () async -> Void
        public init(
            engine: TorrentEngine,
            store: PersistenceStore,
            logger: Logger,
            postProcessor: PostProcessor,
            seedingPolicy: SeedingPolicy,
            healthMonitor: HealthMonitor,
            recoveryCenter: RecoveryCenter,
            diskSpaceMonitor: DiskSpaceMonitor,
            vpnMonitor: VPNMonitor,
            arrNotifier: ArrNotifier,
            forceCyclePort: @escaping @Sendable () async -> Void
        ) {
            self.engine = engine
            self.store = store
            self.logger = logger
            self.postProcessor = postProcessor
            self.seedingPolicy = seedingPolicy
            self.healthMonitor = healthMonitor
            self.recoveryCenter = recoveryCenter
            self.diskSpaceMonitor = diskSpaceMonitor
            self.vpnMonitor = vpnMonitor
            self.arrNotifier = arrNotifier
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
        router.add(middleware: CORSMiddleware())
        router.add(middleware: SecurityHeadersMiddleware(store: services.store))
        router.add(middleware: IPAllowlistMiddleware(store: services.store))

        // qBittorrent Web API v2 compat surface.
        let sessions = QBittorrentAPI.install(
            on: router,
            services: services
        )

        router.add(middleware: AuthMiddleware(sessions: sessions))

        // Static WebUI. Registered last so /api/* routes win.
        StaticWebUI.install(on: router, rootDirectory: configuration.webUIRoot)

        let app = Application(
            router: router,
            configuration: .init(
                address: .hostname(configuration.host, port: configuration.port),
                serverName: Self.serverName
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

    private static var serverName: String {
        if let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String,
           !version.isEmpty {
            return "Controllarr/\(version)"
        }
        return "Controllarr/2.0.0"
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

/// CORS middleware — allows cross-origin requests from the WebUI dev server
/// and any *arr instance that talks to Controllarr. Added before auth so
/// OPTIONS preflight is never blocked by session checks.
struct CORSMiddleware<Context: RequestContext>: RouterMiddleware {
    func handle(
        _ request: Request,
        context: Context,
        next: (Request, Context) async throws -> Response
    ) async throws -> Response {
        // Preflight
        if request.method == .options {
            var headers = HTTPFields()
            headers[.accessControlAllowOrigin] = "*"
            headers[.accessControlAllowMethods] = "GET, POST, DELETE, OPTIONS"
            headers[.accessControlAllowHeaders] = "Content-Type, Cookie"
            headers[.accessControlAllowCredentials] = "true"
            return Response(status: .noContent, headers: headers)
        }
        var response = try await next(request, context)
        response.headers[.accessControlAllowOrigin] = "*"
        response.headers[.accessControlAllowMethods] = "GET, POST, DELETE, OPTIONS"
        response.headers[.accessControlAllowHeaders] = "Content-Type, Cookie"
        response.headers[.accessControlAllowCredentials] = "true"
        return response
    }
}

/// Session-auth middleware — rejects unauthenticated `/api/` requests with 403.
/// Exempt paths: login, logout, version probes, and non-API (static WebUI).
struct AuthMiddleware<Context: RequestContext>: RouterMiddleware {
    let sessions: SessionStore

    /// Paths that never require a session cookie.
    private static var exemptPaths: Set<String> {
        [
            "/api/v2/auth/login",
            "/api/v2/auth/logout",
            "/api/v2/app/version",
            "/api/v2/app/webapiVersion",
        ]
    }

    func handle(
        _ request: Request,
        context: Context,
        next: (Request, Context) async throws -> Response
    ) async throws -> Response {
        let path = request.uri.path
        // Only gate /api/ routes
        guard path.hasPrefix("/api/") else {
            return try await next(request, context)
        }
        // Skip exempt endpoints
        if Self.exemptPaths.contains(path) {
            return try await next(request, context)
        }
        // Validate SID cookie
        guard let sid = QBittorrentAPI.extractSID(from: request),
              await sessions.valid(sid) else {
            return Response(
                status: .forbidden,
                body: .init(byteBuffer: ByteBuffer(string: "Forbidden."))
            )
        }
        return try await next(request, context)
    }
}
