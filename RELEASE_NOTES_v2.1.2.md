# Controllarr v2.1.2

Stability patch for large active torrent libraries.

## Crash Fix

The crash report from the installed app showed `EXC_BAD_ACCESS` inside
`libtorrent::aux::resolver::on_lookup`, with hundreds of active torrents and
multiple libtorrent disk workers running. v2.1.1 kept libtorrent queueing off
by raising every active cap to 10,000, which fixed unwanted auto-pausing but
also let tracker, DHT, and checking work spike too aggressively on large
sessions.

v2.1.2 keeps the no-auto-pause behavior while restoring bounded background
pressure:

- active torrent queue caps still stay high when queueing is disabled
- tracker, DHT, LSD, and checking caps are now kept conservative even when
  queueing is disabled
- the "force reannounce all" path now staggers tracker announces in batches
  instead of kicking every torrent immediately
- DHT/LSD forced announces are limited during mass reannounce operations

## Operator Notes

- If you have hundreds of active torrents, upgrade from the older installed
  app. The crash report showed `Version: 1.0`, so the app in `/Applications`
  was well behind current `main`.
- Queueing can still be enabled from Settings if you want libtorrent to cap
  the number of actively downloading/seeding torrents.
- Leaving queueing off no longer means Controllarr lets all tracker/DNS
  resolver work run unbounded.
