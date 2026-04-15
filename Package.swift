// swift-tools-version: 6.0
import PackageDescription

// Controllarr — Phase 0 proof of concept.
//
// This package exists to prove that Swift can drive libtorrent-rasterbar
// through an Objective-C++ shim on Apple Silicon. Once that's working, the
// full macOS app target (SwiftUI + Hummingbird + React WebUI) will layer on
// top of the same TorrentEngine module defined here.
//
// Required system dependency:
//     brew install libtorrent-rasterbar
//
// Homebrew on Apple Silicon installs to /opt/homebrew, so we point the
// compiler and linker there explicitly.

let brewPrefix = "/opt/homebrew"

let package = Package(
    name: "Controllarr",
    platforms: [
        // libtorrent-rasterbar from Homebrew on this machine is built against
        // a very recent SDK, so we set a high deployment target for the PoC.
        // Phase 1 will pin this against whatever SDK we ship the .app for.
        .macOS(.v15)
    ],
    products: [
        .library(name: "TorrentEngine", targets: ["TorrentEngine"]),
        .executable(name: "ControllarrPoC", targets: ["ControllarrPoC"]),
    ],
    targets: [
        // Objective-C++ shim. Exposes a small C/Objective-C surface that
        // Swift can import cleanly. All libtorrent includes and C++ symbols
        // live behind this wall.
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
                    // OpenSSL from Homebrew is keg-only — its libs live under
                    // /opt/homebrew/opt/openssl@3/lib rather than the main
                    // /opt/homebrew/lib, so it needs its own -L flag.
                    "-L\(brewPrefix)/opt/openssl@3/lib",
                ]),
            ]
        ),

        // Pure-Swift wrapper around the shim. Everything above this line
        // talks Swift types only — no C++ leaks upward.
        .target(
            name: "TorrentEngine",
            dependencies: ["LibtorrentShim"],
            path: "Sources/TorrentEngine"
        ),

        // Phase 0 PoC: add a magnet or .torrent file, print progress until
        // it finishes or the user hits Ctrl-C.
        .executableTarget(
            name: "ControllarrPoC",
            dependencies: ["TorrentEngine"],
            path: "Sources/ControllarrPoC"
        ),
    ],
    cxxLanguageStandard: .cxx17
)
