<p align="center">
  <img src="docs/assets/icon-256.png" alt="Controllarr icon" width="160" height="160" />
</p>

<h1 align="center">Controllarr</h1>

<p align="center">A native macOS BitTorrent client built for Sonarr / Radarr / Overseerr / Plex workflows.</p>

Controllarr uses [libtorrent-rasterbar](https://www.libtorrent.org/) as its engine and wraps it in a Swift + SwiftUI desktop app with both a native macOS window and an embedded React web UI. It speaks the qBittorrent Web API so existing *arr apps can point at it with zero extra configuration.

**Status:** v2.0.1 — fixes torrent-state loss on force-quit / crash by adding add-time `.magnet`/`.torrent` sidecars and a periodic resume-save tick. Built on v2.0.0 which introduced DHT / PeX / LSD peer-discovery toggles, connection-count ceilings, WebUI security headers (X-Frame-Options, CSP frame-ancestors, Referrer-Policy), CIDR IP allowlist, category-aware file moves (torrent reassignment and category-path edits both prompt to relocate files), sortable torrent columns with status-filter dropdown (All / Downloading / Seeding / Completed / Running / Stopped / Active / Inactive / Stalled / Moving / Errored), persisted column widths, a redesigned Settings screen with sidebar tabs and search, per-category torrent list with its own status filter, and menu-bar behavior options (start-minimized, close-to-menu-bar). See [Releases](https://github.com/eMacTh3Creator/Controllarr/releases) for a pre-built binary.

The next major step is a larger **v1.5** release that turns Controllarr from "a Mac-native qBittorrent replacement for *arr apps" into a true download orchestration platform with deeper automation, remote operations, security, and observability. The current roadmap lives in [docs/V1_5_ROADMAP.md](docs/V1_5_ROADMAP.md).

Initial v1.5 foundation work is already landing on `main`: there is now a headless `ControllarrDaemon` executable for always-on nodes, WebUI-driven backup/export/restore, health-based recovery rules plus recovery-center logging, manual post-processing retries, and operator-triggered disk-space rechecks. Usage notes live in [docs/OPERATIONS.md](docs/OPERATIONS.md).

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
- **Keychain credential storage** for the WebUI password and *arr API keys
- **VPN kill switch** — detects VPN tunnel interfaces (PIA, WireGuard, etc.) and pauses all torrents instantly when the VPN drops; auto-resumes on reconnect
- **VPN interface binding** — binds libtorrent's outgoing and listen interfaces to the VPN adapter so torrent traffic never leaks through the default route
- **Network diagnostics** — show bind host, LAN IPs, VPN interface, recommended remote URLs, and warnings when the VPN client is likely blocking LAN ingress
- **Large-library performance tuning** — shared torrent snapshot caching, single-pass session aggregation, balanced libtorrent I/O thread tuning, and lower-overhead polling across the runtime, native UI, and WebUI
- **Disk-space-aware auto-pause** — monitors free space, pauses downloads when below threshold, and exposes operator recheck telemetry in the WebUI
- ***arr re-search integration** — proactive Sonarr/Radarr callbacks when torrents stall
- **Session auth with expiry** — 1-hour token TTL, CORS support, cookie-based middleware
- **Headless daemon executable** — run Controllarr without the app bundle for remote or always-on deployments
- **Backup export / restore** — download the current state as JSON, optionally include Keychain-backed secrets, and restore it from the WebUI
- **Recovery rules and recovery center** — automatically respond to unhealthy torrents, keep an action history of automatic/manual recovery attempts, and pair with manual post-processing retries
- **Per-torrent save path** — `savepath` override from *arr apps wired through to libtorrent
- **.torrent file upload** from the browser WebUI (drag-and-drop or file picker)
- **47-test suite** covering schema migration, archive detection, recovery planning with rule chaining, network diagnostics, post-processing retries, session-summary performance math, Keychain ops, disk-space, *arr endpoints, and VPN monitor
- **Sparkle auto-update** — checks for new versions via appcast and installs in-place
- **Modern React web UI** with live stats, log viewer, settings editor, full category management, and torrent file upload

## Road To v1.5

The big next-wave release should focus on turning Controllarr into a smarter media-delivery control plane rather than just a torrent session wrapper. The highest-impact additions are:

- **Automation and playbooks** — rule-based actions for stalled torrents, import failures, tracker problems, low disk conditions, and post-processing retries
- Progress started: health-based recovery rules now support automatic reannounce/pause/remove actions, failed post-processing jobs can be retried from the WebUI, and disk-space pauses expose explicit operator rechecks
- **Deeper *arr orchestration** — richer Sonarr/Radarr callbacks, approval inboxes, import-readiness checks, re-search policies, and library-aware category templates
- **Remote and distributed control** — headless daemon mode, multi-node management, WebSocket live updates, and a mobile-friendly remote dashboard
- **Security and administration** — multi-user auth, audit logs, scoped API tokens, secret storage, and safer remote exposure defaults
- **Reliability and observability** — health scorecards, recovery workflows, backup/restore, metrics, queue analytics, and better operational visibility
- **Extensibility** — plugin hooks, outbound webhooks, scripting surfaces, and a cleaner public management API

If you want the detailed feature slate, recommended scope, and stretch goals, start with [docs/V1_5_ROADMAP.md](docs/V1_5_ROADMAP.md).

## Documentation

- [docs/README.md](docs/README.md) — documentation index
- [docs/OPERATIONS.md](docs/OPERATIONS.md) — headless daemon usage, backup/export/restore, recovery rules, post-processing retries, and disk-space operations
- [docs/PERFORMANCE.md](docs/PERFORMANCE.md) — large-library behavior, runtime polling model, and scaling guidance for 1,000+ torrents
- [docs/V1_5_ROADMAP.md](docs/V1_5_ROADMAP.md) — proposed big-ticket roadmap for the v1.5 release
- [RELEASE_NOTES_v2.0.1.md](RELEASE_NOTES_v2.0.1.md) — add-time `.magnet`/`.torrent` sidecars and periodic resume-data save, closing the empty-list-after-restart gap
- [RELEASE_NOTES_v2.0.0.md](RELEASE_NOTES_v2.0.0.md) — peer-discovery toggles, connection limits, WebUI hardening, category-aware file moves, Torrents sort/filter, and Settings redesign
- [RELEASE_NOTES_v1.3.0.md](RELEASE_NOTES_v1.3.0.md) — performance and scalability improvements for large torrent libraries
- [RELEASE_NOTES_v1.2.1.md](RELEASE_NOTES_v1.2.1.md) — network diagnostics and remote-LAN VPN troubleshooting
- [RELEASE_NOTES_v0.2.0.md](RELEASE_NOTES_v0.2.0.md) — native UI, post-processing, seeding policy, and health monitor release
- [RELEASE_NOTES_v0.3.0.md](RELEASE_NOTES_v0.3.0.md) — torrent detail panes, trackers/peers, bandwidth scheduler, and API expansion

## Requirements

- Apple Silicon Mac (arm64)
- macOS 15.0+
- [Homebrew](https://brew.sh/)
- `brew install libtorrent-rasterbar`

## Install (pre-built)

Download `Controllarr.zip` from the [latest release](https://github.com/eMacTh3Creator/Controllarr/releases/latest), unzip, and drag `Controllarr.app` into `/Applications`. On first launch you may need to right-click → Open since the binary is ad-hoc signed.

If macOS still blocks launch, you can re-sign the app locally and clear the quarantine flag:

```sh
codesign --force --deep --sign - "/Applications/Controllarr.app" \
  && xattr -rd com.apple.quarantine "/Applications/Controllarr.app"
```

If you installed Controllarr somewhere other than `/Applications`, replace the path in both commands.

Controllarr launches with a native window and a menu-bar status item. The React Web UI is available at <http://127.0.0.1:8791> — default login is `admin` / `adminadmin`. Point Sonarr / Radarr at the same URL using the qBittorrent download client type.

For Sonarr, Radarr, Overseerr, or a browser on another LAN machine, change the WebUI bind host to `0.0.0.0`, restart Controllarr, and then target the Mac's LAN IP such as `http://192.168.1.122:8791`. The `0.0.0.0` value is only for listening; the native app's **Open Web UI** action still opens loopback locally.

## Build from source

```sh
brew install libtorrent-rasterbar xcodegen
cd WebUI && npm install && npm run build && cd ..
xcodegen generate
xcodebuild -project Controllarr.xcodeproj -scheme Controllarr -configuration Release \
  -derivedDataPath /tmp/ControllarrBuild CODE_SIGN_IDENTITY="-"
# Dylibs are embedded automatically by the post-build script.
open /tmp/ControllarrBuild/Build/Products/Release/Controllarr.app
```

The build automatically copies libtorrent-rasterbar and OpenSSL dylibs from Homebrew into the `.app` bundle and rewrites load paths, so the resulting app is self-contained.

The Phase 0 CLI proof-of-concept is still buildable with `swift build` and runs as `.build/debug/ControllarrPoC <magnet-uri>`.

## Headless mode

For an always-on or remote-managed node, run the new daemon executable directly from SwiftPM:

```sh
swift run ControllarrDaemon --webui-root WebUI/dist
```

Optional flags:

- `--state-dir /path/to/state` — override the Application Support directory
- `--host 0.0.0.0` — override the configured bind host for this run
- `--port 8791` — override the configured bind port for this run

The daemon shares the same persistence format and WebUI/API surface as the app bundle, so the same browser UI and *arr integrations keep working.

## License

[MIT](LICENSE) — Controllarr is original work. It reimplements qBittorrent-compatible behavior from public specs; no GPL-licensed qBittorrent source is included or referenced during development.
