# v2.1.14 — Gentle networking for large libraries (configd-reboot mitigation)

This release targets a kernel panic seen on a large always-on node: macOS
force-rebooted because `configd` (the System Configuration / networking daemon)
stopped responding for 180 seconds — a userspace watchdog timeout — after the
app had been running a few hundred torrents for a few hours. That pattern fits
gradual network-resource accumulation, so this release makes Controllarr's
networking noticeably gentler at scale.

## Changed

- **Capped the rate of new peer connections** (`connection_speed`). libtorrent
  opens new connections aggressively by default; Controllarr now caps the rate
  (and lowers it further in large-library mode), which slows the per-second
  socket/network churn that the OS network stack and configd have to process.
- **Large-library mode now engages at ~250 torrents** instead of 650, so the
  reduced tracker/DHT/announce/connection pressure actually applies to typical
  300–500 torrent nodes.
- **VPN interface detection is now sticky.** Machines with several VPN clients
  installed have multiple `utun` devices; the monitor used to grab "the first
  one" each scan and could ping-pong between them, rebinding the listen socket
  repeatedly. It now stays on the interface it's already bound to while that
  interface is up, eliminating that rebind churn.

## Honest scope

This is a **mitigation, not a proven cure.** A userspace app should not be able
to wedge configd; when it happens the proximate cause is usually a lower-level
networking component (a VPN/network kernel filter, or configd itself). These
changes reduce the load Controllarr generates — the most likely trigger — but
can't guarantee the reboots stop. If they persist, the next step is reading
what `configd`/`mDNSResponder` logged right before the hang to pinpoint the
exact subsystem (`scripts/diagnose-configd.sh`).

If you run a large library, update and run it for a day or two. If the reboots
stop, that confirms the mechanism; if not, the diagnostic script will tell us
where to look next.
