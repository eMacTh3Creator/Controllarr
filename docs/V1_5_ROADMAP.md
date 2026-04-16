# Controllarr v1.5 Roadmap

## Vision

v1.5 should be the release where Controllarr stops feeling like "a nicer qBittorrent for Mac" and starts feeling like a dedicated media-download orchestration platform for Sonarr, Radarr, Overseerr, Plex, and power users who want reliability without running a full Linux stack.

The current app already has the right foundation:

- a native macOS UI
- a browser-facing WebUI
- qBittorrent API compatibility
- category-aware post-processing
- seeding policy and health monitoring
- detail panes for files, trackers, and peers

The next big jump is not just adding more toggles. It is adding systems that make Controllarr proactive, explainable, remotely operable, and safer to trust as the center of a media pipeline.

## Foundations Already Started

The first v1.5-oriented pieces are now underway on `main`:

- a new `ControllarrDaemon` executable for headless / always-on deployments
- WebUI backup export and restore workflows
- optional secret export for the WebUI password and saved *arr API keys
- a first-pass health-based recovery engine with automatic/manual action logging
- operator-facing post-processing retries and explicit disk-space rechecks in the WebUI

Those are intentionally infrastructure-heavy changes: they make later work on remote operation, admin features, and reliability much easier to ship cleanly.

## Release Themes

### 1. Download Orchestration

Make the torrent engine policy-driven instead of mostly reactive.

Feature candidates:

- Rule engine for torrent lifecycle events
- Queue profiles for different content types
- Smart auto-tagging based on tracker, category, source app, or filename
- Tracker policy groups with failover behavior
- Automatic recheck / reannounce / pause / delete playbooks
- Batch actions across filtered torrents
- Cross-seed and duplicate-content detection
- Per-category or per-tracker queue budgets
- Download windows and "quiet hours" beyond simple bandwidth caps

Why it matters:

- This moves Controllarr from a client UI into a workflow controller.
- It reduces the amount of manual cleanup Sonarr/Radarr users still do after a torrent is added.

### 2. Deeper *arr Integration

The current qBittorrent compatibility is a strong base, but v1.5 should make Controllarr feel intentionally built for the *arr ecosystem.

Feature candidates:

- Sonarr/Radarr import-readiness checks before a download is considered "healthy"
- Re-search policies based on stalled health state, bad trackers, low availability, or failed import
- Per-app templates for categories, save paths, seeding rules, and blocked file types
- Manual approval inbox for suspect downloads before they continue
- Richer webhook ingestion from Sonarr, Radarr, and Overseerr
- Download lineage view: request -> add -> download -> post-process -> import
- Library-aware rules for anime, movies, UHD remuxes, season packs, and music
- Hardlink / move validation before signaling completion downstream

Why it matters:

- Users do not just want torrents to complete.
- They want media to land in the right place, import cleanly, and self-heal when the pipeline breaks.

### 3. Reliability, Recovery, and Safety

v1.5 should make Controllarr dramatically better at surviving the ugly real-world failure cases.

Feature candidates:

- Health score per torrent instead of only discrete issue rows
- Disk pressure manager with graduated policies instead of a single pause threshold
- Post-processing retry queue with quarantine states and operator notes
- Resume-data and state snapshot backups
- Backup / export / restore for settings, categories, and history
- Recovery center for "why is this stuck?" diagnostics
- VPN policy profiles: hard stop, soft pause, or interface migration
- Startup integrity checks for library paths, permissions, free space, and missing tools
- Automatic "safe mode" launch after repeated crashes

Why it matters:

- Reliability is the feature that converts a clever tool into a daily driver.
- A lot of user trust comes from being able to explain and recover from failures.

### 4. Remote and Distributed Operations

Right now Controllarr is a local Mac app with a built-in WebUI. v1.5 could make it usable as a real control plane.

Feature candidates:

- Headless daemon mode for always-on systems
- Remote-node support so one Mac UI can manage multiple Controllarr instances
- WebSocket push updates instead of full polling everywhere
- Mobile-friendly remote dashboard
- Push notifications for failures, import-ready events, or VPN drops
- Menubar-only deployment mode for tiny always-on hosts
- Lightweight remote agent installer / pairing flow
- Multi-machine handoff of completed downloads

Why it matters:

- A lot of serious *arr users run mixed environments.
- Remote operations massively expand who can use Controllarr and how often they keep it open.

### 5. Security and Administration

The more Controllarr can run remotely or in shared environments, the more important this becomes.

Feature candidates:

- Multi-user accounts with roles
- Read-only operator mode
- Scoped API tokens for apps and automation
- Full audit log of user and automation actions
- Better session management with expiry, revocation, and device history
- Secure secret storage for *arr keys, tracker credentials, and external integrations
- Network access controls and trusted-origin controls for the WebUI
- Encrypted config export for backups

Why it matters:

- Security becomes a product feature once Controllarr moves beyond localhost-only usage.
- Admin features also make the product more supportable and easier to reason about.

### 6. UX and Operator Experience

v1.5 should feel faster and more "control-room" oriented, not just larger.

Feature candidates:

- Global search and command palette
- Saved filters and custom dashboard views
- Activity timeline across adds, health events, post-processing, and imports
- Queue analytics and session charts
- First-run setup wizard for folders, qBit-style creds, and *arr pairing
- Better empty states and explanations for unhealthy torrents
- Inline action history on torrents, categories, and health issues
- Keyboard-first workflows in the native app
- Better responsive layout for the WebUI on tablets and phones

Why it matters:

- A tool that surfaces more power also needs to surface more clarity.
- Operator speed matters if this becomes a "leave open all day" app.

### 7. Extensibility and Ecosystem

This is how Controllarr stops having to ship every integration directly in the core app.

Feature candidates:

- Webhook engine for outgoing events
- Script hooks or actions for advanced operators
- Plugin architecture for integrations and custom policies
- Public REST plus WebSocket management API
- Import/export for templates, rule sets, and category profiles
- Metrics endpoint for Prometheus / Grafana style monitoring
- Event bus or action stream for external automation tools

Why it matters:

- Extensibility makes the app more future-proof.
- It also lowers the pressure to solve every niche request in the core UI.

## Recommended v1.5 Scope

If the goal is a big but coherent v1.5, the release should probably center on these six epics:

1. Rule engine and recovery playbooks
2. Deeper Sonarr/Radarr/Overseerr integration
3. Headless mode plus better remote WebUI
4. Health scorecards and recovery center
5. Multi-user auth, audit log, and API tokens
6. Backup/restore plus signed auto-update flow

That bundle would make the release feel materially different from v1.1 without exploding into a multi-year rewrite.

## Stretch Goals

These are compelling, but they should only land in v1.5 if the core six epics above are already stable:

- Multi-node fleet management
- Plugin SDK
- Mobile push notifications
- Cross-seed assistance
- Import approval inbox
- Metrics / observability dashboards

## Features That Would Feel "Huge" In Marketing

If the goal is also to make the release easy to explain publicly, these are the most headline-worthy:

- "Controllarr can run as a local app or a headless media-download server."
- "Rules and playbooks automatically recover unhealthy torrents."
- "Controllarr understands Sonarr/Radarr import workflows, not just torrent states."
- "You can securely manage multiple nodes and operators from one UI."
- "Built-in backup, restore, updates, and audit trails make it production-friendly."

## Suggested Documentation Follow-Ups

If this roadmap turns into implementation work, the next docs that should exist are:

- architecture overview
- API reference
- operator guide
- remote deployment guide
- security model / auth guide
- backup and restore guide

## Summary

A strong v1.5 release would make Controllarr feel less like a client and more like a media-operations product. The biggest wins are automation, remote control, reliability, and deeper *arr awareness. If those land cleanly, Controllarr becomes something much harder to replace with a generic torrent app.
