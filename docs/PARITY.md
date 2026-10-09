# Platform Coverage and Remaining Work

v2.3.0 aligns common management workflows, not every engine-specific control.
Mac uses libtorrent, Windows uses MonoTorrent, and Controllarr Remote is a remote
client only. Remote now shares adaptive SwiftUI views across iPhone, iPad, and a
separate native Mac target (Apple Silicon and Intel). It does not add engine
features to the Mac server or imply full Windows engine parity.

| Feature | macOS server | Windows server | Remote (iPhone/iPad/Mac) |
| --- | --- | --- | --- |
| Native desktop/mobile UI | SwiftUI | WPF | SwiftUI |
| Adaptive remote sidebar/table/inspector | N/A | N/A | Yes; compact tabs/rows and accessibility fallback |
| Magnet/file intake, categories, bulk pause/remove | Yes | Yes | Yes, selected page |
| Confirmed disk deletion and folder repair | Yes | Yes | Yes, server-side |
| Per-category subfolders / *arr content paths | Yes | Yes | Server settings |
| Files, trackers, peers, force/recheck/reannounce | Yes | Yes | Priorities + diagnostics/controls |
| Seeding, health/recovery, post-processing, schedules | Yes | Yes | Settings/diagnostics, health clear, post retry |
| VPN-bound torrent traffic / LAN control plane | Yes | Yes | Server configuration |
| Remote Protocol 1 + discovery | Yes | Yes | Multiple saved instances |
| Per-torrent speed/connection/sequential/queue ordering | Not full Windows parity | Yes | Not exposed in preview |
| RSS, watch folders, migration and torrent creation | Not full Windows parity | Yes | Not in preview |
| SOCKS5 and IP blocklists | Not full Windows parity | Yes | Server fields where supported |
| Automatic updates | Notarized app + signed Sparkle feed | Release checks; automatic installation planned | Internal TestFlight active; public beta pending |
| Reliable suspended-app notifications | APNs provider not included | APNs provider not included | Best-effort refresh only |

## Reliability Boundaries

Mac checks cover real libtorrent intake/snapshots/checkpoints/removal with 1,000
paused local torrents, unit regressions, release compilation and live isolated
API smoke tests. They do not reproduce a 1,000-active-torrent WAN workload or
identify the cause of prior system-wide restarts. A kernel panic/watchdog report
and persistent app logs are still needed to diagnose that issue confidently.

Windows checks include a real 1,000-torrent engine fixture and loopback
metadata/payload transfers; VM and packaging checks are recorded separately.
ARM64 remains experimental; no long-duration PIA/Nord/provider leak certification
or real Plexbox soak is implied. See the Windows validation report.

iOS has simulator compilation/launch and host protocol tests. The local Xcode
simulator XCTest runner failed to attach to its device service, so host tests
are not represented as successful iPhone XCTest execution. Apple Distribution-signed
device build 1.1.0 (3) passed Transporter validation, completed Apple processing
and is active for internal TestFlight testing. The separate native Mac Remote
1.1.0 binary includes arm64 and x86_64 slices and passes signature, notarization,
stapled-ticket, Gatekeeper and disposable private-Keychain checks. Native Mac
fixture checks covered dashboard, table, inspector and selection across a window
resize. Ten host tests pass. Simulator compilation and headless launch are not
visual rotation tests; physical-device rotation, iPad multitasking, Intel runtime,
public TestFlight/App Store publication and APNs push remain unverified or pending.
See [Remote validation](REMOTE_VALIDATION_1.1.0.md).
