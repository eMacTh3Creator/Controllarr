# Controllarr v2.1.4

Preferred forwarded-port support for VPN users.

## What's New

- Added an optional **Preferred forwarded port** setting for VPN-assigned
  incoming ports, such as PIA's current forwarded port.
- Controllarr now chooses the preferred port before `lastKnownGoodPort` on
  startup.
- Saving a preferred port applies it immediately, reannounces torrents, and
  persists it as the last known good port.
- PortWatcher tries the preferred port before random fallback ports. If the
  preferred port itself is the one that just failed, Controllarr switches to a
  fallback port; if a fallback later fails, it retries the preferred port.
- qBittorrent-compatible `listen_port` preference updates now also set the
  preferred port.

## Operator Notes

- For PIA, set **Preferred forwarded port** to the port shown by the PIA client,
  for example `53127`.
- Leave the setting disabled/blank if your VPN does not provide a stable
  forwarded port.
- This release does not scrape PIA internals automatically. PIA exposes the
  forwarded port differently across client versions, so the safe first step is
  a manual preferred-port setting that works consistently.
