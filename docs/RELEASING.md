# Apple Release Signing

Public macOS v2.3.0 binaries are Developer ID signed with hardened runtime,
notarized by Apple, and stapled. Local open-source builds can remain ad-hoc
signed. Never re-sign a verified release after notarization or ZIP creation.

## macOS Publisher Workflow

Use a valid Developer ID Application certificate with its private key installed
in the build Mac's Keychain and an authorized Xcode Apple account. Do not commit
private keys, passwords or provisioning profiles. Existing certificates must
not be revoked merely to make a new build work.

1. Build WebUI assets and generate the project with XcodeGen.
2. Archive for `generic/platform=macOS`, `ARCHS=arm64`, manual Developer ID signing,
   and `CONTROLLARR_ENTITLEMENTS` pointing to `App/Controllarr.release.entitlements`.
3. Run `bash Scripts/sign-macos.sh ARCHIVE/Products/Applications/Controllarr.app IDENTITY`
   to sign nested frameworks/helpers inside out. Sparkle helper entitlements are preserved.
4. Upload with `xcodebuild -exportArchive`, the archive path, and
   `Scripts/ExportOptions-DeveloperID.plist`. The checked-in export options contain
   the project's public team ID only; other publishers must substitute their own.
5. After Apple processing, run `xcodebuild -exportNotarizedApp` with the same archive
   and a new export directory. A processing archive is not a successful notarization.
6. Require `codesign --verify --deep --strict`, `xcrun stapler validate`, and
   `spctl --assess --type execute --verbose=4` to pass on the exported app.
7. Launch an immutable copy with isolated `CONTROLLARR_STATE_DIR` and
   `CONTROLLARR_HTTP_PORT`; verify authenticated APIs and graceful native quit.
8. ZIP with `ditto -c -k --sequesterRsrc --keepParent`, then re-extract and repeat
   ticket/Gatekeeper verification. Generate checksums from those exact ZIP bytes.
9. Sign the final ZIP with `Scripts/update-appcast.py`. Use a secure publisher
   `SPARKLE_PRIVATE_KEY` environment or explicit `--allow-keychain`. Never put a
   private key in a command argument, repository, app bundle or release asset.
10. Verify the Ed25519 signature/archive length, upload assets, verify GitHub's
    SHA-256 digests, then publish the release before activating the new appcast.

Publisher-only Keychain prompts can occur when a new signing key is first used.
Installed desktop apps never read the release-signing keys. WebUI login does not
read macOS Keychain. Normal first-launch/network prompts are distinct from signing
or notarization failures.

See Apple's [notarization workflow](https://developer.apple.com/documentation/security/customizing-the-notarization-workflow).

## iOS Distribution

The remote manager uses `com.controllarr.remote`, not the Mac torrent-engine app
identifier. App Store distribution needs an explicit App ID, Apple Distribution
certificate/private key, matching App Store Connect provisioning profile, and
an App Store Connect app record. `iOS/ExportOptions-AppStore.plist` contains the
publisher's public team/profile names, not secrets.

Use an App Store Connect-supported release or release-candidate Xcode/SDK. A
beta macOS host does not require using a beta Xcode; install release Xcode
alongside it and select that toolchain with `DEVELOPER_DIR` for the entire archive
and export process. Do not change SDK metadata to disguise an unsupported build.
Check Apple's [current releases](https://developer.apple.com/news/releases/).

The icon generator has a separate iOS mode which produces a full-bleed 1024px
RGB image without an alpha channel. Do not copy the transparent macOS icon:

```sh
swift Scripts/make-icon.swift iOS/Sources/Assets.xcassets/AppIcon.appiconset/icon.png --ios
```

Generate the iOS project after changing `iOS/project.yml`. Retain all four iPad
orientations and the launch-screen declaration for multitasking support. Archive
with manual distribution signing, verify `get-task-allow` is false, and run the
bundle checks before exporting:

```sh
swift iOS/Scripts/check-release.swift /path/to/ControllarrRemote.xcarchive/Products/Applications/ControllarrRemote.app
codesign --verify --deep --strict /path/to/ControllarrRemote.xcarchive/Products/Applications/ControllarrRemote.app
```

Upload through Xcode/App Store Connect. If Xcode's account/provider lookup fails,
export an App Store Connect-signed IPA with export option `destination=export`
and deliver that exact file with Apple's Transporter app. Do not revoke valid
certificates to work around an account lookup error. Transporter validation and
App Store Connect build processing must both succeed.

An archive or signed IPA is not itself
a public iPhone installation method. Only advertise a TestFlight link after
Apple accepts/processes the build and the beta group is actually available.
Public testing may require beta review. Physical-device and notification-delivery
checks remain separate from signing validation.
