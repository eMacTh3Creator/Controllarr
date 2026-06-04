# Controllarr v2.1.3

Hotfix for a confirmed v2.1.2 resolver crash under a large active torrent
library.

## Crash Fix

A new crash report from `Version: 2.1.2` showed Controllarr ran for nearly two
days before crashing inside `libtorrent::aux::resolver::on_lookup`. The stack
also showed macOS DNS/mDNS lookup work active at the same time. This confirms
that v2.1.2's startup storm protection was not conservative enough for
sustained 700+ torrent operation.

v2.1.3 moves large-library networking into a stricter resolver-protection mode:

- tracker-announcing torrents are capped much lower
- concurrent HTTP tracker announces are capped at 6
- libtorrent's resolver cache is kept warm for longer
- failing trackers back off more aggressively
- multi-tracker fanout is disabled so libtorrent does not announce to every
  tracker/tier in parallel
- mass reannounce operations are spread over up to 10 minutes instead of
  scheduling hundreds of announces in a short burst

## Operator Notes

- This release is specifically for users with hundreds of active torrents or
  VPN/DNS environments that trigger sustained resolver pressure.
- Queueing still defaults to off, so torrents should not silently auto-pause.
  The tighter limits affect background announce/check work, not whether a
  torrent is allowed to accept peers.
- If another `Version: 2.1.3` crash appears in the same resolver path, the next
  step is likely a libtorrent dependency upgrade or an operator-facing
  "conservative tracker mode" toggle that can disable DHT/LSD and further
  reduce tracker announces.
