# Controllarr v2.1.7

This release turns Sparkle auto-update support into a production-ready weekly
update flow.

## What's Changed

- Adds a Sparkle Ed25519 public update key to the app bundle.
- Enables weekly scheduled update checks with user prompts.
- Adds a native Settings toggle to turn weekly update checks on or off.
- Keeps automatic installation disabled, so operators choose when to download
  and apply an available update.
- Bumps `CFBundleVersion` to `217` so Sparkle can compare this and future
  updates correctly.
- Refreshes `appcast.xml` with a signed release enclosure.
- Adds `Scripts/update-appcast.py` so future releases can update the appcast
  using either Sparkle's Keychain-backed private signing key or a
  `SPARKLE_PRIVATE_KEY` CI secret.

## Notes

The private Sparkle signing key is stored in the macOS Keychain under the
`com.controllarr.updates` account and is not committed to the repository.
On local release machines, macOS may ask once for `sign_update` to access that
Keychain item; choosing **Always Allow** avoids repeated prompts. Installed
copies of Controllarr do not need Keychain access to check for updates.

Users on older builds may need to install this release manually once. After
that, Controllarr can check weekly and prompt when a newer signed update is
available.
