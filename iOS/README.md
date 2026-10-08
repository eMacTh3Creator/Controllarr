# Controllarr Remote (iOS Preview)

Native SwiftUI iPhone/iPad manager for macOS and Windows Controllarr v2.3.0+.
Requires iOS 17+, Xcode with an iOS SDK, and XcodeGen. No torrent engine runs on iOS.
See [setup and notification limits](../docs/MOBILE.md) and [platform coverage](../docs/PARITY.md).

```sh
cd iOS
xcodegen generate
xcodebuild -project ControllarrRemote.xcodeproj -scheme ControllarrRemote \
  -configuration Release -sdk iphonesimulator \
  -destination 'generic/platform=iOS Simulator' \
  -derivedDataPath /tmp/ControllarrRemoteBuild CODE_SIGNING_ALLOWED=NO build
```

Host-only protocol tests, separate from simulator/device UI tests:

```sh
swift test --scratch-path /tmp/ControllarrRemoteProtocolBuild
```

For a physical device or TestFlight, select your valid Apple Developer team in
Xcode, use a registered bundle identifier, archive for iOS, then distribute
through App Store Connect. This preview does not include provisioning profiles,
private signing keys, APNs credentials or an installable public IPA. A simulator
build cannot run on an iPhone. The publisher has created valid Apple certificates,
the explicit App ID, an App Store provisioning profile and the App Store Connect
record. The distribution-signed archive passes signature validation with
`get-task-allow=false`. Corrected device build 1.0.0 (2) was delivered through
Apple Transporter on October 8, 2026, processed by Apple and enabled in the
publisher's internal TestFlight testing group. Public TestFlight access is not available yet; do not treat the
simulator download as a phone installer.

Publisher upload options are in `ExportOptions-AppStore.plist`; other developers
must substitute their own team/profile. See [release signing](../docs/RELEASING.md).
Distribution builds must use an Apple-supported release/RC Xcode and SDK, even
when the build Mac runs a beta macOS. The project declares all four iPad
orientations for multitasking, and the iOS icon is opaque RGB rather than the
transparent macOS artwork. Run `Scripts/check-release.swift` against the archived
device `.app` before exporting or uploading. Apple's Transporter can deliver an
exported App Store Connect-signed IPA if Xcode account lookup fails.

Passwords use the iOS app's private Keychain without requiring user-presence
authentication. They are not included in project files or backups of instance
metadata. HTTP is opt-in; HTTPS uses normal certificate validation and rejects
redirects. Server hostnames can include an HTTPS reverse-proxy base path.

Local notifications use foreground polling and best-effort background refresh.
This is explicitly not a reliable APNs push implementation.
