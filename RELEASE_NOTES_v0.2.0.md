# Controllarr v0.2.0

Controllarr v0.2.0 turns the Phase 1 proof-of-concept into a much more complete desktop torrent controller for the *arr ecosystem.

## Highlights

- Added a native macOS window with dedicated tabs for Torrents, Categories, Settings, Health, Post-Processor, Seeding, and Log.
- Upgraded the browser-facing WebUI to match the native app's management surface, including category editing, settings, health, post-processing, seeding visibility, and log filtering.
- Added post-processing services for move-storage, archive extraction, and completion tracking.
- Added seeding-policy enforcement with ratio and time limits, including minimum-seed-time protection for hit-and-run rules.
- Added torrent health monitoring with stall detection and optional automatic reannounce.
- Expanded the persistence schema to cover completion paths, archive extraction, blocked extensions, seeding limits, and health-monitor configuration.
- Expanded the qBittorrent-compatible API surface and added `/api/controllarr/*` endpoints for richer remote administration.

## Native App

- Controllarr now launches as a regular Dock app while keeping the menu-bar status item as a quick control surface.
- The native window is backed by a shared runtime view model that polls the live torrent/session state every two seconds.
- Categories can now define initial save paths, completion destinations, blocked file extensions, archive extraction rules, and per-category seeding overrides.

## Remote Control

- The bundled WebUI now exposes:
  - torrent monitoring and magnet intake
  - full category CRUD
  - full settings editing
  - health issue review and clearing
  - post-processing and seeding activity views
  - live log filtering
- qBittorrent-compatible endpoints remain available for Sonarr, Radarr, Overseerr, and related tooling.

## Under the Hood

- Added libtorrent shim support for file listing, file priorities, and manual reannounce.
- Added service actors for logging, post-processing, seeding policy, and health monitoring.
- Added settings migration support so older on-disk state rolls forward into the new schema.

## Smoke-Test Notes

- Release app built successfully from `project.yml` at marketing version `0.2.0`.
- Verified the Release app launches as a visible regular app and exposes the local WebUI on `http://127.0.0.1:8791/`.
- Verified status-item creation through macOS scene logs.
- Verified category and settings persistence across relaunch.
- Verified qBittorrent-compatible login and torrent-info endpoints still respond.
