<p align="center">
  <img src="docs/assets/icon-256.png" alt="Controllarr icon" width="160" height="160" />
</p>

<h1 align="center">Controllarr</h1>

<p align="center">A Mac-native torrent control center for Sonarr, Radarr, Overseerr, Plex, and always-on media servers.</p>
<p align="center">
  <a href="https://emacth3creator.github.io/Controllarr/">Public website</a> ·
  <a href="https://github.com/eMacTh3Creator/Controllarr/releases/latest">Download latest release</a> ·
  <a href="docs/README.md">Documentation</a>
</p>

Controllarr is a native macOS BitTorrent client powered by [libtorrent-rasterbar](https://www.libtorrent.org/). It gives you a SwiftUI desktop app, a browser-based React WebUI, a menu-bar controller, and qBittorrent Web API compatibility so Sonarr, Radarr, and Overseerr can use it as a drop-in download client.

The project is built around a common media-server pain point: torrent traffic should stay on the VPN, but the WebUI and *arr API should remain reachable from another LAN machine. Controllarr includes VPN interface binding, LAN-aware WebUI settings, network diagnostics, and preferred forwarded-port support for providers such as PIA.

**Current status:** Controllarr is public and usable, with active releases focused on VPN-safe operation, qBittorrent API compatibility, large-library stability, and smoother native/WebUI controls.

## Why Controllarr?

- Run a Mac mini as a dedicated torrent target for Sonarr, Radarr, Overseerr, and Plex workflows.
- Keep torrent traffic bound to a VPN adapter while still exposing the WebUI/API to your LAN.
- Use qBittorrent-compatible endpoints without running qBittorrent itself.
- Handle big libraries with 700 to 1,000+ torrents more conservatively than a generic desktop torrent UI.
- Manage categories, post-processing, seeding policy, health, recovery, logs, and network diagnostics from one app.

## Highlights

- **qBittorrent Web API v2 compatibility** for Sonarr, Radarr, Overseerr, and other qBit-aware tools.
- **Native macOS app** with Torrents, Categories, Settings, Health, Recovery, Post-Processor, Seeding, and Log views.
- **Modern React WebUI** for browser access from the Mac or another machine on the LAN.
- **Automatic listen-port cycling** when a port appears stale or unhealthy.
- **Preferred forwarded port** for VPN providers such as PIA, with fallback to a configured port range.
- **VPN kill switch and VPN interface binding** so torrent traffic can stay on the tunnel adapter.
- **Network diagnostics** showing bind host, LAN URLs, detected VPN interface, and likely remote-access problems.
- **Category-based routing** with save paths, complete paths, archive extraction, blocked extensions, and seeding overrides.
- **Post-processing pipeline** for moving completed torrents and extracting `.rar`, `.zip`, and `.7z` archives.
- **Seeding policy** with ratio limits, seed-time limits, and minimum-seed-time protection.
- **Health monitoring and recovery rules** for stalled torrents, post-processing failures, disk pressure, and manual recovery.
- **Large-library tuning** with shared torrent snapshots, reduced tracker/DNS pressure, staggered reannounce behavior, and lower-overhead polling.
- **Torrent detail panes** for files, trackers, and peers, including per-file priority controls.
- **Bandwidth scheduler**, connection limits, peer-discovery toggles, duplicate detection, force recheck, and force resume.
- **Keychain-backed secrets**, session auth, WebUI hardening, backup export/restore, and weekly Sparkle update prompts.
- **Headless daemon mode** for always-on nodes that do not need the full app window.

## Quick Install

1. Download the newest macOS zip from the [latest GitHub release](https://github.com/eMacTh3Creator/Controllarr/releases/latest).
2. Unzip it and move `Controllarr.app` to `/Applications`.
3. Right-click `Controllarr.app` and choose **Open** the first time.

If macOS still blocks launch, self-sign the app and clear quarantine:

```sh
codesign --force --deep -s - /Applications/Controllarr.app
xattr -rd com.apple.quarantine /Applications/Controllarr.app
```

The app is currently ad-hoc signed. If you install it somewhere other than `/Applications`, replace the path in both commands.

Controllarr checks weekly for signed Sparkle updates and prompts when a newer
release is available. It does not silently install updates.

## First Run

Controllarr opens a native macOS window and also serves the WebUI at:

```text
http://127.0.0.1:8791
```

Default login:

```text
Username: admin
Password: adminadmin
```

Change the default password in Settings before exposing the WebUI beyond the Mac.

## Connecting Sonarr, Radarr, and Overseerr

Use the qBittorrent download-client type in Sonarr/Radarr and point it at Controllarr:

```text
Host: 127.0.0.1
Port: 8791
Username: admin
Password: adminadmin
```

If Sonarr/Radarr/Overseerr runs on another LAN machine, set Controllarr's **WebUI bind host** to:

```text
0.0.0.0
```

Then restart Controllarr and target the Mac's LAN IP, for example:

```text
http://192.168.1.122:8791
```

`0.0.0.0` is only the listen address. Local open actions still use loopback on the Mac.

## VPN and Port Forwarding

For a setup like PIA on the torrent Mac and Sonarr/Radarr on another machine:

- Set the WebUI bind host to `0.0.0.0` so LAN clients can reach the API.
- Keep torrent traffic bound to the VPN interface using the VPN protection settings.
- Set **Preferred forwarded port** to the port your VPN provider gives you, for example `53127`.
- Keep a fallback listen-port range configured so Controllarr can cycle if the preferred port goes stale.
- Use Network Diagnostics if the WebUI works locally but another LAN machine cannot connect while the VPN is enabled.

This design separates control traffic from torrent traffic: the API/WebUI can be reachable on the LAN while libtorrent remains bound to the VPN adapter.

## Releases

- Latest release: [github.com/eMacTh3Creator/Controllarr/releases/latest](https://github.com/eMacTh3Creator/Controllarr/releases/latest)
- All release notes: [github.com/eMacTh3Creator/Controllarr/releases](https://github.com/eMacTh3Creator/Controllarr/releases)
- Public website: [emacth3creator.github.io/Controllarr](https://emacth3creator.github.io/Controllarr/)

Recent release line:

- **v2.1.7:** signed Sparkle appcast, weekly update checks, an on/off switch, and prompted downloads.
- **v2.1.6:** consistent typed port inputs across native and WebUI.
- **v2.1.5:** preferred forwarded-port text box hotfix.
- **v2.1.4:** preferred VPN forwarded-port support.
- **v2.1.3:** resolver-pressure hotfix for sustained 700+ torrent operation.
- **v2.1.2:** large-library stability improvements.
- **v2.1.1:** Force Resume and configurable libtorrent queueing.
- **v2.1.0:** duplicate detection, force recheck, context menus, multi-select operations, and stronger port-cycle reconnect.
- **v2.0.0:** peer-discovery toggles, connection limits, WebUI hardening, category-aware file moves, and Settings redesign.

## Roadmap

The old "Road To v1.5" plan has largely become the current product direction: headless mode, recovery rules, backup/restore, VPN protection, performance tuning, network diagnostics, and deeper WebUI operations have already started landing.

The next major wave should focus on making Controllarr feel less like a torrent client and more like a media-download operations platform:

- **Smarter automation:** richer rule playbooks for stalled torrents, failed imports, tracker problems, post-processing retries, and disk pressure.
- **Deeper *arr orchestration:** Sonarr/Radarr/Overseerr callbacks, import-readiness checks, re-search policy, approval queues, and category templates per app.
- **Remote operations:** WebSocket live updates, mobile-friendly dashboards, multi-node management, and better headless deployment workflows.
- **Reliability and observability:** health scorecards, queue analytics, recovery timelines, metrics, and clearer "why is this stuck?" diagnostics.
- **Security and administration:** multi-user auth, scoped API tokens, audit logs, trusted-origin controls, and safer remote-exposure defaults.
- **Extensibility:** webhooks, scripting hooks, public management APIs, and eventually plugin-style integrations.

The longer-form planning document still lives at [docs/V1_5_ROADMAP.md](docs/V1_5_ROADMAP.md), but the README now treats that as historical/product-direction context rather than a pending v1.5 release target.

## Documentation

- [docs/README.md](docs/README.md) — documentation index.
- [docs/OPERATIONS.md](docs/OPERATIONS.md) — headless usage, backups, recovery rules, post-processing retries, disk-space operations, and VPN/LAN guidance.
- [docs/PERFORMANCE.md](docs/PERFORMANCE.md) — scaling notes for large torrent libraries and 1,000+ torrent operation.
- [docs/V1_5_ROADMAP.md](docs/V1_5_ROADMAP.md) — original long-form roadmap and future product themes.
- [docs/index.html](docs/index.html) — GitHub Pages landing page.
- [Release notes](https://github.com/eMacTh3Creator/Controllarr/releases) — full version history.

## Build From Source

Requirements:

- Apple Silicon Mac.
- macOS 15.0 or newer.
- Xcode command line tools.
- Homebrew.
- `libtorrent-rasterbar` and `xcodegen`.

Build:

```sh
brew install libtorrent-rasterbar xcodegen
cd WebUI
npm install
npm run build
cd ..
xcodegen generate
xcodebuild -project Controllarr.xcodeproj -scheme Controllarr -configuration Release \
  -derivedDataPath /tmp/ControllarrBuild CODE_SIGN_IDENTITY="-"
open /tmp/ControllarrBuild/Build/Products/Release/Controllarr.app
```

The build embeds Homebrew libtorrent/OpenSSL dylibs into the app bundle and rewrites load paths so the release app is self-contained.

SwiftPM test/build commands:

```sh
swift test
swift build
```

## Headless Mode

Run the daemon executable directly for an always-on node:

```sh
swift run ControllarrDaemon --webui-root WebUI/dist
```

Optional flags:

- `--state-dir /path/to/state` overrides the Application Support state directory.
- `--host 0.0.0.0` overrides the configured bind host for this run.
- `--port 8791` overrides the configured bind port for this run.

The daemon uses the same persistence format and WebUI/API surface as the app bundle.

## Project Status

Controllarr is public and usable, but it is still moving quickly. The safest production posture is:

- Keep backups of your Controllarr state.
- Use VPN binding and the kill switch if torrent traffic must never leak.
- Use the Network Diagnostics panel when exposing the WebUI to another LAN machine.
- Watch release notes before upgrading a heavily loaded 700+ torrent node.

## License

[MIT](LICENSE). Controllarr is original work. It reimplements qBittorrent-compatible behavior from public specs; no GPL-licensed qBittorrent source is included or referenced during development.
