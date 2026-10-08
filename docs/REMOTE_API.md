# Remote Protocol 1

All routes use the existing `/api/v2/auth/login` username/password and `SID`
cookie. No new unauthenticated admin endpoint or permanent bearer token exists.
TLS is supplied by a trusted reverse proxy/private network, not by the embedded
HTTP listener. Do not expose plaintext credentials over the public Internet.

| Route | Contract |
| --- | --- |
| `GET /api/controllarr/remote` | `protocol=1`, platform, version, settingsStyle, supported features, notification transport |
| `GET /api/controllarr/remote/torrents` | `search`, exact `category`, nonnegative `offset`, `limit` 1-500 (default 100); returns `total`, `offset`, `items` |
| `GET /api/controllarr/remote/events` | `epoch`, `cursor`; returns epoch/cursor/reset/events, maximum 512 retained events |
| `POST /api/controllarr/torrents/{hash}/repairLayout` | URL-encoded `confirmed=true`; metadata required, conflicts rejected; Mac move acceptance is asynchronous |
| `POST /api/v2/torrents/setLocation` | URL-encoded `hashes` joined with pipes, absolute server `location`; preserve owned subfolder |
| `POST /api/v2/torrents/reannounce` | URL-encoded `hashes` |
| `POST /api/v2/torrents/recheck` | URL-encoded `hashes` |

Paged torrent rows use qBittorrent names including `hash`, `content_path`,
`save_path`, state, rates and category. Ordering is stable by info hash; pages
are not transactional snapshots across simultaneous additions/removals.
Refresh a page after mutations. Search is case-insensitive. Existing qBit and
Controllarr categories/settings/files/health routes remain available.

Settings/categories use camelCase on Mac and snake_case on Windows, declared
by capabilities. Clients must preserve unknown fields and merge only their
changes into a fresh settings document. Do not write a partial JSON object into
a full-replacement settings API. Successful settings saves do not imply that
listen-host/port or discovery changes are live before a restart.

Event fields: numeric `id`, `kind`, `title`, `message`, nullable `hash`, Unix
seconds `timestamp`. Kinds are `completed`, `error`, `vpn_disconnected`,
`port_changed`. The initial/mismatched/stale cursor returns `reset=true` and
no replay; store its new epoch/cursor as the baseline. Events are observed on a
three-second cadence, not persisted. Short transitions between samples may be
missed. Polling transport does not provide reliable iOS background push.

Run `node Scripts/test-remote-api.mjs` only against a disposable profile with
default test credentials; use `CONTROLLARR_TEST_URL` for a non-default address.
The fixture creates/removes only its uniquely named category/torrent.
