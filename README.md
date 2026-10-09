<p align="center">
  <img src="docs/assets/icon-256.png" alt="Controllarr icon" width="160" height="160" />
</p>

<h1 align="center">Controllarr</h1>

<p align="center">A Mac torrent client that connects to Sonarr and Radarr.</p>
<p align="center">
  <a href="https://emacth3creator.github.io/Controllarr/">Public website</a> ·
  <a href="https://github.com/eMacTh3Creator/Controllarr/releases/latest">Download latest release</a> ·
  <a href="docs/README.md">Documentation</a>
</p>

Controllarr is a Mac BitTorrent client using [libtorrent-rasterbar](https://www.libtorrent.org/). Manage transfers in the desktop app, from the menu bar, or in a browser. Sonarr and Radarr connect using the qBittorrent download-client type; Overseerr sends requests through those apps.

Choose a VPN adapter for torrent traffic while keeping browser and API access available on your LAN. The app includes network diagnostics and forwarded-port settings for providers such as PIA.

**v2.3.0:** bounded resume checkpointing, lower-overhead snapshots, session-level VPN startup/disconnect protection, two-worker archive extraction, category subfolder controls, and corrected Sonarr content paths. Native tables support confirmed pause-first bulk removal, including category selection and the Delete key. Existing storage is not silently reorganized; use **Repair import folder layout** when needed.

**Controllarr Remote 1.1:** manage torrents from an iPhone, iPad, or Mac. Sort transfers, select several torrents at once, and inspect files. The remote app connects to an existing server; it does not run a torrent engine. See [installation](iOS/README.md), [setup](docs/MOBILE.md), and [remote release notes](RELEASE_NOTES_remote-v1.1.0.md).

[Download Mac Remote 1.1.0 (Apple Silicon + Intel)](https://github.com/eMacTh3Creator/Controllarr/releases/download/remote-v1.1.0/ControllarrRemote-v1.1.0-macOS-universal.zip). Requires macOS 15+. Developer ID signed, notarized and stapled; move `ControllarrRemote.app` to Applications and connect to an existing server. iPhone/iPad build 1.1.0 (3) is available to the existing internal TestFlight group. See [Remote release notes](RELEASE_NOTES_remote-v1.1.0.md).

Windows x64/ARM64 installers live in the [Windows project](https://emacth3creator.github.io/Controllarr-Windows/). The engines and advanced controls are not identical across platforms.

## What it does

- Run a Mac mini as a dedicated torrent target for Sonarr, Radarr, Overseerr, and Plex workflows.
- Keep torrent traffic bound to a VPN adapter while still exposing the WebUI/API to your LAN.
- Use qBittorrent-compatible endpoints without running qBittorrent itself.
- Manage larger libraries with limits on background saves and tracker lookups.
- Manage categories, post-processing, seeding policy, health, recovery, logs, and network diagnostics from one app.

## Highlights

- **qBittorrent Web API v2 compatibility** for Sonarr, Radarr, Overseerr, and other qBit-aware tools.
- **Native macOS app** with Torrents, Categories, Settings, Health, Recovery, Post-Processor, Seeding, and Log views.
- **Browser Web UI** for browser access from the Mac or another machine on the LAN.
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
- **Saved credentials**, session auth, WebUI hardening, backup export/restore, and weekly Sparkle update prompts without login-time Keychain dialogs.
- **Headless daemon mode** for always-on nodes that do not need the full app window.

## Quick Install

1. Download the newest macOS zip from the [latest GitHub release](https://github.com/eMacTh3Creator/Controllarr/releases/latest).
2. Unzip it and move `Controllarr.app` to `/Applications`.
3. Open `Controllarr.app` normally.

The v2.3.0 Mac release is Developer ID signed, Apple notarized and stapled.
No self-signing or quarantine-removal command is needed. macOS can still show
its normal first-launch confirmation and network permission prompts. Do not
re-sign the downloaded app: that replaces its verified publisher signature.
If macOS reports a damaged or unverified download, download a fresh copy from
the official release rather than disabling security checks.

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

- **v2.3.0:** Mac resource/lifecycle hardening, clean category folders and Sonarr import compatibility, shared remote protocol and native iOS source/simulator preview.
- **v2.1.15:** persistent on-disk log that survives crashes/reboots, plus a "Reveal Log File" button for post-mortem diagnosis.
- **v2.1.14:** gentler networking for large libraries (capped new-connection rate, large-library mode engages at ~250 torrents, sticky VPN interface) to mitigate configd-watchdog reboots.
- **v2.1.13:** critical fix for a launch crash in 2.1.11/2.1.12 on Macs without Homebrew (library paths are now fully self-contained, enforced by a build gate).
- **v2.1.12:** native Home dashboard mirroring the WebUI, a torrents search box with one-click clear-to-neutral, and smoother large-library scrolling. *(Crashes at launch without Homebrew — use 2.1.13.)*
- **v2.1.11:** embeds a defensively hardened libtorrent 2.0.12 (re-entrancy-safe DNS resolver callback handling) for large-library crash resistance.
- **v2.1.10:** resolver-mode hysteresis so large libraries no longer flap protection near the threshold, lower-overhead session stats, and a clear notice when a legacy WebUI password is reset during migration.
- **v2.1.9:** adds automatic conservative resolver protection for 650+ torrent sessions to prevent VPN/DNS resolver crashes.
- **v2.1.8:** removes remote-login Keychain prompts by keeping WebUI and *arr credentials in portable app state.
- **v2.1.7:** signed Sparkle appcast, weekly update checks, an on/off switch, and prompted downloads.
- **v2.1.6:** consistent typed port inputs across native and WebUI.
- **v2.1.5:** preferred forwarded-port text box hotfix.
- **v2.1.4:** preferred VPN forwarded-port support.
- **v2.1.3:** resolver-pressure hotfix for sustained 700+ torrent operation.
- **v2.1.2:** large-library stability improvements.
- **v2.1.1:** Force Resume and configurable libtorrent queueing.
- **v2.1.0:** duplicate detection, force recheck, context menus, multi-select operations, and stronger port-cycle reconnect.
- **v2.0.0:** peer-discovery toggles, connection limits, WebUI hardening, category-aware file moves, and Settings redesign.

## Development plans

See [the roadmap](docs/V1_5_ROADMAP.md) for planned automation, remote management, and administration features.

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

### Patched libtorrent (optional, used by official releases)

Official release builds embed a locally built, defensively hardened libtorrent
2.0.12 (`patches/libtorrent-2.0.12-resolver-reentrancy.patch`) instead of the
stock Homebrew dylib. It makes `resolver::on_lookup` re-entrancy-safe as
extra insurance on large 700+ torrent libraries. The two are the same version
and ABI-identical, so the app still links against Homebrew at build time and
only the *embedded* runtime copy changes.

To produce it (requires `cmake`):

```sh
brew install cmake
./scripts/build-patched-libtorrent.sh   # installs into vendor/libtorrent-patched/
```

`scripts/embed-dylibs.sh` automatically prefers `vendor/libtorrent-patched/`
when present and silently falls back to the Homebrew dylib otherwise, so this
step is optional for local development.

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

## Running a media server

A few things to set up before leaving Controllarr running unattended:

- Keep backups of your Controllarr state.
- Select your VPN adapter and enable your provider's kill switch.
- Use the Network Diagnostics panel when exposing the WebUI to another LAN machine.
- Read the release notes before upgrading.

### Credential storage

Since v2.1.8, Controllarr keeps the WebUI password and *arr API keys in its
portable app-state file rather than the macOS Keychain. This is what stops the
repeated Keychain prompts seen with older ad-hoc public builds, but it also means those
secrets are stored in clear text inside the Application Support state
directory. Protect that directory with normal file permissions, and do not
share your raw state file. When upgrading from an older Keychain-backed build,
if macOS cannot read your saved WebUI password without prompting, Controllarr
resets it to the default `adminadmin` and logs a notice — set a new password in
Settings before exposing the WebUI to your network.

## License

[MIT](LICENSE). Controllarr is original work. It reimplements qBittorrent-compatible behavior from public specs; no GPL-licensed qBittorrent source is included or referenced during development.
