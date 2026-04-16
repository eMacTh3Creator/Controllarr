<p align="center">
  <img src="docs/assets/icon-256.png" alt="Controllarr icon" width="160" height="160" />
</p>

<h1 align="center">Controllarr</h1>

<p align="center">A native macOS BitTorrent client built for Sonarr / Radarr / Overseerr / Plex workflows.</p>

Controllarr uses [libtorrent-rasterbar](https://www.libtorrent.org/) as its engine and wraps it in a Swift + SwiftUI desktop app with both a native macOS window and an embedded React web UI. It speaks the qBittorrent Web API so existing *arr apps can point at it with zero extra configuration.

**Status:** Phase 3 — full-featured `.app` with native UI, qBittorrent Web API compatibility, React WebUI, post-processing pipeline, seeding policy, health monitoring, bandwidth scheduler, and per-torrent file/tracker/peer detail. See [Releases](https://github.com/eMacTh3Creator/Controllarr/releases) for a pre-built binary.

## Features

- **Automatic listen-port reselection** when the forwarded port goes offline (the #1 reason this project exists)
- **qBittorrent Web API v2** compatibility — Sonarr / Radarr / Overseerr work without custom integration
- **Native macOS window** with sidebar navigation: Torrents, Categories, Settings, Health, Post-Processor, Seeding, Log
- **Per-torrent detail**: file picker (skip/enable individual files), tracker status, live peer list
- **Category-based save paths** and post-complete move rules for Plex library handoff
- **Archive extractor** (.rar / .zip / .7z) via macOS bsdtar
- **Dangerous-file filter** per category with blocked extension lists
- **Seeding policy** — per-category or global max ratio / max seed time with hit-and-run protection
- **Health monitoring** — stall detection with reason codes, auto-reannounce recovery
- **Bandwidth scheduler** — time-of-day download/upload rate limiting
- **Keychain credential storage** for the WebUI password
- **18-test suite** covering schema migration, archive detection, policy enums, and Keychain ops
- **Modern React web UI** with live stats, log viewer, settings editor, and full category management

## Planned

- *arr re-search integration (proactive Sonarr/Radarr callbacks on stalled torrents)
- Sparkle auto-update
- Disk-space-aware auto-pause

## Requirements

- Apple Silicon Mac (arm64)
- macOS 15.0+
- [Homebrew](https://brew.sh/)
- `brew install libtorrent-rasterbar`

## Install (pre-built)

Download `Controllarr.zip` from the [latest release](https://github.com/eMacTh3Creator/Controllarr/releases/latest), unzip, and drag `Controllarr.app` into `/Applications`. On first launch you may need to right-click → Open since the binary is ad-hoc signed.

Controllarr launches with a native window and a menu-bar status item. The React Web UI is available at <http://127.0.0.1:8791> — default login is `admin` / `adminadmin`. Point Sonarr / Radarr at the same URL using the qBittorrent download client type.

## Build from source

```sh
brew install libtorrent-rasterbar xcodegen
cd WebUI && npm install && npm run build && cd ..
xcodegen generate
xcodebuild -project Controllarr.xcodeproj -scheme Controllarr -configuration Release \
  -derivedDataPath /tmp/ControllarrBuild CODE_SIGN_IDENTITY="-"
open /tmp/ControllarrBuild/Build/Products/Release/Controllarr.app
```

The Phase 0 CLI proof-of-concept is still buildable with `swift build` and runs as `.build/debug/ControllarrPoC <magnet-uri>`.

## License

[MIT](LICENSE) — Controllarr is original work. It reimplements qBittorrent-compatible behavior from public specs; no GPL-licensed qBittorrent source is included or referenced during development.
