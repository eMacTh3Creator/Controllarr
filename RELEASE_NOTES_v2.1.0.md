# Controllarr v2.1.0

Feature release focused on qBittorrent-parity torrent management. v2.1.0
turns Controllarr into a real operator tool: duplicate-torrent handling
that matches qBittorrent's semantics, force-recheck, right-click context
menus on the Torrents table and Categories list, multi-select for
batched operations, and a stronger port-cycle reconnect kick.

## What's new

### Duplicate-torrent detection

Previously, adding a magnet or `.torrent` whose info-hash matched a
torrent already in the session was a silent no-op at the shim boundary
and surfaced as a confusing "add failed" in the logs. The Sonarr /
Radarr re-add flow (which happens constantly on retry) made this
especially noisy.

2.1.0 adds first-class duplicate detection. Every add request goes
through a duplicate-aware path that first parses the incoming info-hash
from the magnet / `.torrent` and checks it against the live session.
If it matches an existing torrent, the new **Duplicate torrent policy**
setting decides what to do:

- **Ignore the re-add** — silently drop the duplicate. Existing torrent
  stays untouched. Useful for environments where Sonarr/Radarr
  aggressively retry.
- **Merge new trackers into existing torrent** (default — matches
  qBittorrent's behavior) — parse trackers from the incoming request
  and union-merge them into the existing torrent via
  `torrent_handle::add_tracker`. Duplicate URLs are skipped.
- **Ask each time** (native UI only) — surface a prompt sheet listing
  the incoming trackers and let the operator pick merge or ignore.
  WebUI / *arr callers fall back to "Merge" since they're
  non-interactive.

The qBittorrent Web API `/api/v2/torrents/add` endpoint now returns
`200 OK` in the duplicate case (with the existing info-hash) rather
than logging a failure, so Sonarr / Radarr integrations stop filling
up the log with spurious errors.

### Force Recheck

New **Force Recheck** action on every torrent. Equivalent to
qBittorrent's "Force Recheck": libtorrent re-hashes all on-disk files
and reconciles pieces. If you already have most of the data on disk
(e.g. you copied files in manually or recovered a partial download
from another client), force-recheck lets Controllarr pick up from
where you actually are instead of redownloading everything.

Exposed via the right-click context menu on the Torrents table, the
inline action bar below the table, and as a bulk action when multiple
rows are selected.

### Right-click context menus

- **Torrents table** — right-click a row (or selection) for:
  - Pause / Resume
  - Force Recheck
  - Reannounce
  - Open in Finder (reveals the torrent's save path, selecting the
    torrent's top-level file/folder when possible)
  - Copy submenu (Magnet Link, Name, Info Hash)
  - Category submenu (re-assign; honors the Category Change Move
    policy)
  - Remove (keep files) / Remove and delete files

- **Categories list** — right-click a category for:
  - Edit…
  - View Torrents
  - Open Save Path in Finder
  - Open Complete Path in Finder (when set)
  - Copy Name / Copy Save Path
  - Delete Category

Double-clicking a torrent row reveals it in Finder, matching
qBittorrent's default primary action.

### Multi-select and mass operations

The Torrents table is now multi-select: Cmd-click or Shift-click rows
to build a selection. All of the toolbar actions and context-menu
actions operate on the whole selection — mass pause, mass resume, mass
force-recheck, mass reannounce, mass remove (with or without deleting
files). A "N selected" indicator appears in the action bar when more
than one row is selected.

### Port-cycle now actively reconnects

When `PortWatcher` cycles the listen port — either automatically
after a stall or via the **Cycle Listen Port Now** menu-bar action —
the shim's `forceReannounceAll` now:

- Calls `force_reannounce(0, -1, ignore_min_interval)` so every
  tracker reannounces immediately, bypassing the per-tracker minimum
  announce-interval backoff
- Calls `force_dht_announce` on every torrent so peers on the DHT
  learn the new listen port immediately
- Calls `force_lsd_announce` on every torrent for Local Service
  Discovery

Result: after a port cycle the client actively pushes the new port
out through every available discovery channel instead of waiting
for the next scheduled announce.

### Duplicate-policy selector in Settings

Settings gained a **Duplicate torrents** section with the new policy
picker and an explanatory caption about WebUI / *arr fallback
behavior.

## Behind the scenes

- **LibtorrentShim** gained seven new methods: `infoHashForMagnet:`,
  `infoHashForTorrentFile:`, `trackersInMagnet:`,
  `trackersInTorrentFile:`, `hasTorrent:`, `addTrackersToTorrent:trackers:`,
  `forceRecheckTorrent:`, and `makeMagnetForTorrent:`.
- **TorrentEngine** gained a duplicate-aware `addMagnet` / `addTorrentFile`
  overload that returns a new `TorrentAddResult` enum
  (`.added` / `.duplicateIgnored` / `.duplicateMergedTrackers` /
  `.duplicatePrompt`). The legacy add-returns-hash calls still work,
  so callers can migrate at their own pace.
- **Persistence** gained a new `DuplicateTorrentPolicy` enum
  (`ignore` / `mergeTrackers` / `ask`) and `Settings.duplicateTorrentPolicy`
  field with backward-compat `decodeIfPresent` so old `state.json`
  files upgrade cleanly with `mergeTrackers` as the default.
- **RuntimeViewModel** now exposes `forceRecheck(hash:)`,
  `addTrackers(_:to:)`, `openInFinder(hash:)`, `copyMagnet(hash:)`,
  and a `pendingDuplicate` state that drives the native prompt sheet.

## Upgrade notes

Drop-in release. No schema migration required. Existing torrents
preserve their state through the shim changes (the `force_reannounce`
enhancement is additive, and the duplicate-detection helpers only
fire on *new* add requests).

If you integrate with Sonarr / Radarr, consider leaving
**Duplicate torrent policy** on its default **Merge new trackers into
existing torrent** — this matches qBittorrent exactly and is the
quietest setting for aggressive retry loops.
