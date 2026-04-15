# Controllarr

A native macOS BitTorrent client built for Sonarr / Radarr / Overseerr / Plex workflows.

Controllarr uses [libtorrent-rasterbar](https://www.libtorrent.org/) as its engine and wraps it in a Swift + SwiftUI app with an embedded React web UI. It speaks the qBittorrent Web API so existing *arr apps can point at it with zero extra configuration.

**Status:** Phase 0 — libtorrent integration proof of concept. Not usable yet.

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

## Build (Phase 0)

```sh
swift build
.build/debug/ControllarrPoC <magnet-uri-or-torrent-file>
```

## License

[MIT](LICENSE) — Controllarr is original work. It reimplements qBittorrent-compatible behavior from public specs; no GPL-licensed qBittorrent source is included or referenced during development.
