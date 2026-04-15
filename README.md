<p align="center">
  <img src="docs/assets/icon-256.png" alt="Controllarr icon" width="160" height="160" />
</p>

<h1 align="center">Controllarr</h1>

<p align="center">A native macOS BitTorrent client built for Sonarr / Radarr / Overseerr / Plex workflows.</p>

Controllarr uses [libtorrent-rasterbar](https://www.libtorrent.org/) as its engine and wraps it in a Swift + SwiftUI menu-bar app with an embedded React web UI. It speaks the qBittorrent Web API so existing *arr apps can point at it with zero extra configuration.

**Status:** Phase 1 — menu-bar `.app` with qBittorrent Web API compatibility, React WebUI, and automatic listen-port reselection. See [Releases](https://github.com/eMacTh3Creator/Controllarr/releases) for a pre-built binary.

## Planned features

- Automatic listen-port reselection when the forwarded port goes offline (the #1 reason this project exists)
- qBittorrent Web API compatibility so Sonarr / Radarr / Overseerr work without custom integration
- Category-based save paths and post-complete move rules for Plex library handoff
- Dangerous-file filter per category
- Built-in archive extractor for `.rar` and `.zip`
- Hit-and-run obligation tracking with per-tracker thresholds
- Torrent health monitoring — stall detection, auto-blacklist, re-search triggers
- Overseerr/Ombi request puller with user-priority weighting
- Per-tracker seeding policy (ratio, time, tracker injection)
- Disk-space-aware auto-pause
- Modern React web UI with live stats, log viewer, and config editor
- Sparkle auto-update

## Requirements

- Apple Silicon Mac (arm64)
- macOS 14+ (target TBD)
- [Homebrew](https://brew.sh/)
- `brew install libtorrent-rasterbar`

## Install (pre-built)

Download `Controllarr.zip` from the [latest release](https://github.com/eMacTh3Creator/Controllarr/releases/latest), unzip, and drag `Controllarr.app` into `/Applications`. On first launch you may need to right-click → Open since the binary is ad-hoc signed.

Controllarr runs as a menu-bar accessory (no Dock icon). Click the menu-bar glyph to open the Web UI at <http://127.0.0.1:8791> — default login is `admin` / `adminadmin`. Point Sonarr / Radarr at the same URL using the qBittorrent download client type.

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
