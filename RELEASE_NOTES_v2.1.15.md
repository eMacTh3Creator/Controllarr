# v2.1.15 — Persistent logs that survive crashes

A small but useful release for diagnosing problems (like the large-library
reboots) after they happen.

## Added

- **Persistent log file.** Controllarr now mirrors its runtime log to disk at
  `~/Library/Application Support/Controllarr/logs/controllarr.log`, flushed
  frequently (and immediately on warnings/errors) so it survives an app crash
  or a full machine reboot. It rotates at ~5 MB and keeps one previous file.
  Previously the log lived only in memory and was lost when the app or the Mac
  went down — which is exactly when you need it.
- **Reveal Log File button** in the Log tab opens that file in Finder, so you
  can grab it after a crash without touching the Terminal.

## Where macOS keeps the kernel/app crash logs

For completeness: the app can't record a *kernel panic* (the whole machine
halts), but macOS saves those automatically and they survive reboots — open
**Console.app → Crash Reports** and look for a `.panic` (kernel) or `.ips`
(app) report. Between that and the new on-disk Controllarr log, a crash now
leaves a full trail: what Controllarr was doing, plus what the system recorded.

Carries forward the v2.1.14 large-library networking mitigations.
