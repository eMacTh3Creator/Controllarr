# Remote 1.1.0 Validation

Recorded October 9, 2026. Shared source version 1.1.0, build 3. Release toolchain:
Xcode 27.0 (27A266a), iOS/macOS 27.0 SDKs, not the installed beta Xcode.

## Passed

- Ten host tests: protocol/address security, form encoding, event/JSON handling,
  settings merge, layout thresholds, accessibility fallback, safe pagination
  after mass deletion and workspace selection/destination retention.
- iOS Simulator Debug compilation and disconnected fixture headless launches
  on iPhone and iPad simulators.
- iOS release archive and distribution signature with `get-task-allow=false`.
  Release preflight verifies all four iPad orientations, opaque app icon and SDK.
- Apple Transporter delivery of 1.1.0 (3), completed Apple processing and
  App Store Connect status **Testing** in the existing internal group.
- Native Mac compilation for `arm64` and `x86_64`; macOS 15 deployment target.
- Developer ID signature, hardened runtime, sandbox and embedded matching
  provisioning profile with app-specific data-protection Keychain entitlement.
- Disposable Keychain save, load, update and delete using the shipped credential
  implementation in a separately signed sandbox test bundle. No real saved
  credentials were read, modified or logged; no credential-access dialog appeared.
- Apple notarization, stapled ticket, strict signature and Gatekeeper acceptance
  on the exported app and a fresh extraction of the final release ZIP.
- Native Mac disconnected fixture: dashboard, 100 loaded torrent rows from a
  2,400-item library, sortable table, selection, inspector and OS window resize.
  Selection survived the resize. Fixture data is excluded from Release.

## Not Verified or Not Included

- A simulator GUI was unavailable in the installed toolchain. Compilation and
  headless launch are not visual iPhone rotation or iPad multitasking tests.
- Physical-device UI/notification checks and Intel Mac runtime/soak testing.
- Long-running live-server or thousands-of-torrents engine load certification.
  The remote uses bounded pages; it does not run a local torrent engine.
- External/public TestFlight, App Store approval, reliable APNs delivery,
  iCloud profile sync and an automatic updater for the separate Mac remote.
- Root cause of earlier whole-system Mac server restarts; no new panic logs were
  supplied for this remote-interface update.

The macOS torrent server remains v2.3.0 with its existing release/appcast.
Windows binaries are unchanged. Remote uses the already-shipped Remote Protocol 1.
