## Controllarr v0.3.0

### Per-torrent detail (Files, Trackers, Peers)

- **File picker**: select a torrent to see its full file list with sizes and download priorities. Toggle individual files between "Normal" and "Skip" to exclude unwanted content.
- **Trackers**: view every tracker's status (Working / Error / Not contacted), tier, seed/peer/leecher counts, and last tracker message.
- **Peers**: live peer list showing client name, progress, download/upload speed, and connection flags.
- All three detail views are available in both the native macOS window (split pane below the torrent table) and the browser WebUI (expandable panel on torrent click).

### New libtorrent shim APIs

- `trackersForInfoHash:` — reads `lt::announce_entry` and scrape data
- `peersForInfoHash:` — reads `lt::peer_info` with qBittorrent-style flags
- `fileInfoForInfoHash:` — file names, sizes, and current download priorities
- `setRateLimitsDownloadKBps:uploadKBps:` — global bandwidth limiting

### Bandwidth scheduler

- Time-of-day download/upload rate limiting. Define rules by day-of-week + time window + speed cap.
- Managed in the Settings tab (both native UI and WebUI).
- Evaluates every 60 seconds; first matching rule wins; no rule = unlimited.

### Keychain credential storage

- Added `Persistence/Keychain.swift` — uses Security.framework (`SecItemAdd`/`SecItemCopyMatching`) to store sensitive strings outside the plaintext JSON state file. Prepared for WebUI password and future *arr API keys.

### HTTP API additions

**qBittorrent-compat endpoints:**
- `GET /api/v2/torrents/files?hash=` — full qBit-format file list
- `GET /api/v2/torrents/trackers?hash=` — qBit-format tracker list
- `GET /api/v2/torrents/pieceStates?hash=` — stub (empty array)

**Controllarr-native endpoints:**
- `GET /api/controllarr/torrents/:hash/files` — native file info
- `POST /api/controllarr/torrents/:hash/files` — set file priorities
- `GET /api/controllarr/torrents/:hash/trackers` — native tracker info
- `GET /api/controllarr/torrents/:hash/peers` — native peer info

### Persistence schema

- Added `BandwidthRule` type with `name`, `enabled`, `daysOfWeek`, start/end time, `maxDownloadKBps`, `maxUploadKBps`.
- `Settings.bandwidthSchedule` — array of bandwidth rules, defaults to empty. Existing v0.2.0 state files roll forward automatically via the custom decoder.

### Test suite

- 18 tests covering Persistence schema migration, PostProcessor archive detection, SeedingPolicy enums, HealthMonitor reason codes, and Keychain operations.
- Uses Swift Testing framework (`@Test` + `#expect()`).

### Install

Download `Controllarr-v0.3.0-macOS-arm64.zip`, unzip, right-click the app and choose **Open** to bypass Gatekeeper (ad-hoc signed). Requires macOS 15.0+.
