# v2.1.10 — Large-library resolver hardening + migration safety

This hotfix follows up v2.1.9's resolver crash guard with stability, efficiency,
and credential-migration improvements found during a focused code-review pass.

## Fixed

- **Resolver-mode hysteresis.** Conservative protection now engages at 650
  torrents but only relaxes once the count drops below 580, so a library
  hovering near the threshold no longer flaps libtorrent settings on every
  poll. The decision logic is now unit-tested.
- **Lower-overhead session stats.** The session-stats path no longer walks the
  full torrent list twice per refresh, reducing per-poll overhead on 700+
  torrent nodes.
- **Clear migration notice.** When upgrading from an older Keychain-backed
  build, if macOS cannot read your saved WebUI password without prompting,
  Controllarr resets it to the default and now logs a visible security notice
  so you know to set a new password before exposing the WebUI.

## Notes

- Credentials are stored in Controllarr's portable app state (clear text in the
  Application Support directory) since v2.1.8. Protect that directory and avoid
  sharing your raw state file. See the README "Credential storage" section.
- The underlying libtorrent resolver behavior is unchanged upstream; v2.1.9 and
  v2.1.10 reduce the resolver pressure Controllarr can create under heavy
  torrent counts. If you are running hundreds of active torrents, stay current.
