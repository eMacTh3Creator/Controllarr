# v2.1.9 — Large-library resolver crash guard

This hotfix responds to a new crash report from a 700+ torrent library where Controllarr 2.1.5 crashed inside `libtorrent::aux::resolver::on_lookup` shortly after launch.

## Fixed

- Added automatic conservative resolver protection for sessions with roughly 650 or more torrents.
- Resume directories are scanned before torrents are re-added, so large-library protection engages before startup restore can schedule hundreds of tracker lookups.
- Large sessions now lower active tracker, DHT, LSD, and concurrent HTTP announce pressure.
- Resolver cache lifetime and tracker backoff are increased in conservative mode.
- Mass reannounce operations, including port-cycle reannounce, are spread much more slowly for large libraries and skip forced DHT/LSD bursts.

## Why this matters

The crash was in libtorrent's DNS resolver path, not SwiftUI or the WebUI. A user-space app crash should not normally reboot macOS, but sustained VPN/DNS resolver pressure can make the whole machine unstable. This release treats that path as high-risk and reduces the amount of resolver work Controllarr can create under heavy torrent counts.

If you are running hundreds of active torrents, upgrade from 2.1.5 or older as soon as possible.
