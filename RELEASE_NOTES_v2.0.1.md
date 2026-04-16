# Controllarr v2.0.1

Patch release that fixes torrent-state loss across restarts.

## What's fixed

Before 2.0.1, the torrent list could come back empty after a relaunch.
Resume data was only being written at shutdown and only for torrents
that had already fetched their metadata, so anything killed by a
force-quit, crash, power loss, or pre-metadata magnet was gone forever.

2.0.1 closes that gap in three ways:

- **Add-time sidecars.** Every `addMagnet` and `addTorrentFile` call
  now writes a small recovery file (`<infohash>.magnet` or
  `<infohash>.torrent` + `.path`) next to the `.fastresume` directory
  under `~/Library/Application Support/Controllarr/resume/`. Even a
  crash seconds after adding a torrent leaves a recoverable breadcrumb.
- **Periodic resume save.** The runtime tick loop now asks libtorrent
  to serialize fastresume data roughly every 30 seconds while the app
  is running, so in-progress torrents always have an up-to-date
  snapshot on disk.
- **Expanded restore path.** On launch, the shim first loads every
  `.fastresume` (same as before), then scans the same directory for
  `.magnet` and `.torrent` sidecars and re-adds anything whose info
  hash didn't come back via fastresume.

Sidecars are deleted when a torrent is removed, so the directory doesn't
grow forever.

## Upgrade notes

Drop-in patch. No config changes, no state migration. Open the app once
and any torrents you add from here on will survive a force-quit.

Existing torrents that were lost in a previous crash cannot be recovered
retroactively — they were never written to disk in the first place.

## Files changed at runtime

- `~/Library/Application Support/Controllarr/resume/<hash>.fastresume`
  — libtorrent fastresume (unchanged, now refreshed every 30s)
- `~/Library/Application Support/Controllarr/resume/<hash>.magnet`
  — line 1: magnet URI, line 2: save path (new)
- `~/Library/Application Support/Controllarr/resume/<hash>.torrent`
  — raw .torrent bytes (new)
- `~/Library/Application Support/Controllarr/resume/<hash>.path`
  — save path for the .torrent sidecar (new)
