// swift-tools-version: 6.0
import PackageDescription

// Controllarr — Phase 1.
//
// Library package that hosts every reusable module. The SwiftUI .app target
// is defined separately via xcodegen (see project.yml) and depends on the
// products below through Swift Package Manager.
//
// Required system dependencies (Apple Silicon / Homebrew):
//     brew install libtorrent-rasterbar

let brewPrefix = "/opt/homebrew"

let package = Package(
    name: "Controllarr",
    platforms: [
        .macOS(.v15)
    ],
    products: [
        .library(name: "TorrentEngine",  targets: ["TorrentEngine"]),
        .library(name: "Persistence",    targets: ["Persistence"]),
        .library(name: "PortWatcher",    targets: ["PortWatcher"]),
        .library(name: "HTTPServer",     targets: ["HTTPServer"]),
        .library(name: "ControllarrCore",targets: ["ControllarrCore"]),
        .executable(name: "ControllarrPoC", targets: ["ControllarrPoC"]),
    ],
    dependencies: [
        .package(url: "https://github.com/hummingbird-project/hummingbird.git", from: "2.0.0"),
    ],
    targets: [
        // MARK: - Libtorrent wall (Obj-C++)
        .target(
            name: "LibtorrentShim",
            path: "Sources/LibtorrentShim",
            publicHeadersPath: "include",
            cxxSettings: [
                .define("TORRENT_USE_OPENSSL"),
                .unsafeFlags([
                    "-I\(brewPrefix)/include",
                    "-std=c++17",
                    "-fobjc-arc",
                ]),
            ],
            linkerSettings: [
                .linkedLibrary("torrent-rasterbar"),
                .linkedLibrary("c++"),
                .linkedLibrary("ssl"),
                .linkedLibrary("crypto"),
                .unsafeFlags([
                    "-L\(brewPrefix)/lib",
                    "-L\(brewPrefix)/opt/openssl@3/lib",
                ]),
            ]
        ),

        // MARK: - Swift-native torrent engine (actor wrapper)
        .target(
            name: "TorrentEngine",
            dependencies: ["LibtorrentShim"],
            path: "Sources/TorrentEngine"
        ),

        // MARK: - JSON-backed state store
        .target(
            name: "Persistence",
            path: "Sources/Persistence"
        ),

        // MARK: - Port reachability watcher / auto-reselect
        .target(
            name: "PortWatcher",
            dependencies: ["TorrentEngine", "Persistence"],
            path: "Sources/PortWatcher"
        ),

        // MARK: - Embedded HTTP server + qBittorrent Web API compatibility
        .target(
            name: "HTTPServer",
            dependencies: [
                "TorrentEngine",
                "Persistence",
                .product(name: "Hummingbird", package: "hummingbird"),
            ],
            path: "Sources/HTTPServer"
        ),

        // MARK: - Umbrella: composes engine + persistence + http + port watcher
        .target(
            name: "ControllarrCore",
            dependencies: [
                "TorrentEngine",
                "Persistence",
                "PortWatcher",
                "HTTPServer",
            ],
            path: "Sources/ControllarrCore"
        ),

        // MARK: - Phase 0 PoC executable (still useful as a smoke test)
        .executableTarget(
            name: "ControllarrPoC",
            dependencies: ["TorrentEngine"],
            path: "Sources/ControllarrPoC"
        ),
    ],
    cxxLanguageStandard: .cxx17
)
