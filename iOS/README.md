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
`get-task-allow=false`. TestFlight publication is still pending Apple upload and
processing; do not treat the simulator download as a phone installer.

Publisher upload options are in `ExportOptions-AppStore.plist`; other developers
must substitute their own team/profile. See [release signing](../docs/RELEASING.md).

Passwords use the iOS app's private Keychain without requiring user-presence
authentication. They are not included in project files or backups of instance
metadata. HTTP is opt-in; HTTPS uses normal certificate validation and rejects
redirects. Server hostnames can include an HTTPS reverse-proxy base path.

Local notifications use foreground polling and best-effort background refresh.
This is explicitly not a reliable APNs push implementation.
