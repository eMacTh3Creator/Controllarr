# Controllarr v2.1.1

Bug-fix release. Fixes a long-standing "torrents randomly pause themselves"
behavior, adds a proper Force Resume action, and makes libtorrent's queue
system a real, configurable setting instead of an accidental default.

## What's fixed

### Root cause: torrents pausing themselves

In v2.1.0 and earlier, the shim's `setConnectionLimitsGlobalConnections:…`
helper wrote its `connectionsPerTorrent` argument into libtorrent's
`settings_pack::active_limit` — which is not a connection cap at all, it's
the session-wide queueing cap on the number of concurrently active
auto-managed torrents. Past that count, libtorrent silently pauses excess
torrents. Combined with libtorrent's default active-* caps (3 downloads /
5 seeds / 15 total), any reasonably sized library would see torrents
"pause themselves" once the session got past the threshold.

v2.1.1 fixes this three ways:

1. **Session queueing is off by default.** At session startup, all
   active-* caps (`active_downloads`, `active_seeds`, `active_checking`,
   `active_dht_limit`, `active_tracker_limit`, `active_lsd_limit`,
   `active_limit`) are raised to 10,000. Queueing never kicks in unless
   the operator turns it on.
2. **Per-torrent connection caps go to the right place.** The shim now
   applies `connectionsPerTorrent` / `uploadsPerTorrent` via
   `torrent_handle::set_max_connections` / `set_max_uploads` on every
   running torrent instead of abusing `active_limit` / `active_seeds`.
3. **Queueing is a real Settings toggle.** If you actually want a queue,
   turn on **Enable libtorrent queueing** under Settings → Torrent
   queueing and configure the active-downloads / active-seeds /
   active-limit caps yourself.

### Force Resume (Force Download)

New **Force Resume** action — libtorrent's equivalent of qBittorrent's
"Force Start" / "Force Download". Takes a torrent out of the auto-managed
pool so the queue system can never silently re-pause it, regardless of
the active-* caps.

Exposed three ways:
- Right-click a torrent (or a selection of torrents) and choose
  **Force Resume**
- `POST /api/v2/torrents/setForceStart` with `hashes` and `value=true`
  (qBittorrent-compatible)
- Programmatically via `TorrentEngine.forceResume(infoHash:)` /
  `RuntimeViewModel.forceResume(hash:)`

### Auto-promote when queueing is on

When queueing is enabled, libtorrent's auto-managed system automatically
promotes the next queued torrent whenever a running one finishes, is
paused, or is removed. This is free — Controllarr's `resume(infoHash:)`
already puts torrents back into the auto-managed pool, so queued
torrents will drain out as active slots open up without any operator
action. Use **Force Resume** to pin a specific torrent past the caps.

## New Settings section

**Settings → Torrent queueing** gained:

- **Enable libtorrent queueing** toggle (off by default)
- Max active downloads / Max active seeds / Max active torrents overall
  steppers, shown only when queueing is enabled
- Inline caption explaining that queued torrents auto-resume when active
  slots open up, and that Force Resume bypasses the caps per-torrent

## Behind the scenes

- **LibtorrentShim** gained `forceResumeTorrent:` (resume + unset
  `auto_managed`) and
  `setQueueingEnabled:activeDownloads:activeSeeds:activeLimit:` (writes
  all the active-* keys in a single `apply_settings` call, honoring
  the enabled flag).
- **Persistence** gained a `TorrentQueueing` struct
  (`enabled` / `activeDownloads` / `activeSeeds` / `activeLimit`) and
  `Settings.torrentQueueing`, with `decodeIfPresent` backward-compat so
  old `state.json` files upgrade cleanly with queueing off.
- **TorrentEngine** gained `forceResume(infoHash:)` and
  `applyQueueing(enabled:activeDownloads:activeSeeds:activeLimit:)`.
- **ControllarrCore** applies the queueing settings alongside connection
  limits on boot and whenever the operator saves Settings.
- **qBittorrent API** gained `/api/v2/torrents/setForceStart` for parity
  with qBittorrent clients.

## Upgrade notes

Drop-in release. No schema migration. Existing torrents are unaffected.

If you were seeing torrents "randomly pause" on v2.1.0 or earlier, those
torrents are still paused because libtorrent wrote the paused state to
their resume data. After upgrading, select them and hit Resume (or Force
Resume if you want them to stay active regardless of any future queue
settings).
