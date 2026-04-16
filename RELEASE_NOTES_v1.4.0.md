# Controllarr v1.4.0

This release focuses on operator control — WebUI hardening, peer discovery
toggles, connection-count ceilings, category-move workflows, and table
sorting/filtering in the native UI.

## What's new

### Category-aware file moves
- **Switching a torrent's category now moves its files** to the new
  category's save path (honors a new `categoryChangeMove` policy:
  `ask` / `always` / `never`).
- **Editing a category's save path** prompts the operator whether to
  move every torrent tagged with that category to the new location.
  Choosing "Leave them" keeps the files in place for manual relocation.
- Exposed at the engine layer as `setCategory(_:for:moveFiles:)` and
  `moveCategoryMembers(_:to:)`; wired into both the qBittorrent compat
  API (`/api/v2/torrents/setCategory`, `/editCategory` — each accepts an
  optional `moveFiles` form field that overrides the persisted policy)
  and the native UI's category editor.

### Peer discovery controls
- New `Settings.peerDiscovery` surface: DHT, PeX, and LSD toggles.
  DHT and LSD apply at runtime via `settings_pack`; PeX applies on the
  next session restart (libtorrent 2.x doesn't expose a runtime toggle
  for the ut_pex extension).

### Connection-count ceilings
- New `Settings.connectionLimits`: global connections, per-torrent
  connections, global unchoked uploads, per-torrent unchoked uploads.
  Any value left at nil inherits libtorrent's default.
- Applied on boot (`ControllarrRuntime.applyNetworkSettings()`) and
  re-applied whenever the operator saves Settings.

### WebUI hardening
- **Security response headers:** `X-Content-Type-Options: nosniff`,
  `Referrer-Policy: no-referrer` on every response, and
  `X-Frame-Options: DENY` + `Content-Security-Policy: frame-ancestors 'none'`
  when clickjacking protection is enabled.
- **IP allowlist (CIDR):** Optional deny-by-default mode. Loopback is
  always permitted so the operator never locks themselves out. IPv4 and
  IPv6 CIDR masks are both supported; bare IPs are treated as /32 or
  /128 exact matches. Honors `X-Forwarded-For` for operators running
  behind a reverse proxy.
- **CSRF opt-in** and **clickjacking opt-in** as persisted settings.

### Torrents tab — sort + filter
- **Sortable columns**: Name, Size, Progress, ↓, ↑, Peers, Ratio all
  support the native macOS column-sort affordance.
- **Status filter dropdown** with the 11 states Everett asked for:
  All, Downloading, Seeding, Completed, Running, Stopped, Active,
  Inactive, Stalled, Moving, Errored. The selected filter persists
  across launches via `UIPreferences.torrentStatusFilter`.

### Persistence schema additions (backward compatible)
- `UIPreferences` — column widths map, sort key/direction, status filter,
  menu-bar / start-minimized / close-to-menu-bar prefs.
- `PeerDiscovery` — dhtEnabled, pexEnabled, lsdEnabled.
- `ConnectionLimits` — global + per-torrent connection and upload caps.
- `WebUISecurity` — allowlistEnabled, allowedCIDRs, clickjackingProtection,
  csrfProtection.
- `CategoryMovePolicy` — ask / always / never.
- All fields default to safe values and use `decodeIfPresent` so existing
  settings files roll forward cleanly.

## Upgrade notes

Delete nothing — the v1.3.0 settings file is fully backward-compatible
with v1.4.0. Open Settings once after upgrading to surface the new
peer-discovery and security controls.

## Known limitations

- The qBittorrent `/api/v2/torrents/setCategory` endpoint defers to the
  persisted `categoryChangeMove` policy when the `moveFiles` form field
  is omitted. If the policy is `ask`, the API defaults to no-move — the
  native UI is where the prompt lives.
- PeX toggling takes effect on the next session restart (libtorrent 2.x
  design limitation).
- The IP allowlist is enforced against the socket-level remote address
  when available; if Controllarr sits behind a reverse proxy, that proxy
  must forward `X-Forwarded-For` or all traffic will appear to come from
  the proxy's IP.
