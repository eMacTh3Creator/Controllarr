# Controllarr Remote for iPhone, iPad, and Mac

Native SwiftUI remote manager for macOS and Windows Controllarr v2.3.0+.
Requires iOS/iPadOS 17+ or macOS 15+, release Xcode, and XcodeGen. No torrent
engine runs in the remote manager. The existing Mac server app stays separate.
See [setup and notification limits](../docs/MOBILE.md) and [platform coverage](../docs/PARITY.md).

## Install

[Download Mac Remote 1.1.0](https://github.com/eMacTh3Creator/Controllarr/releases/download/remote-v1.1.0/ControllarrRemote-v1.1.0-macOS-universal.zip)
for Apple Silicon and Intel, macOS 15+. Unzip, move `ControllarrRemote.app` to
Applications, and open normally. This binary is Developer ID signed, Apple
notarized and stapled. Do not self-sign it or remove security protections.
Normal macOS first-launch and local-network permission prompts may still appear.
Mac Remote currently uses manual downloads for updates.

iPhone/iPad users in the publisher's existing internal TestFlight group can
install **1.1.0 (3)** through TestFlight. No public invitation link is available.

## Adaptive Workspace

- iPhone and narrow iPad windows use four tabs and touch-friendly torrent rows.
- Larger iPad windows and Mac use a sidebar with direct access to operations.
- Wider transfer panes use sortable, multi-select tables with a file/control
  inspector alongside the list. Narrow panes and accessibility text use rows;
  the inspector becomes a system sheet where appropriate.
- The dashboard expands into a command grid and side-by-side recent activity.
- Search, category filters, selection, and the active section survive layout
  changes. Controls reflow instead of assuming portrait orientation.
- Mac includes native menus, right-click actions, Delete-to-confirm removal,
  Command-N intake, Command-R refresh, and Command-comma instance management.
- Loading and sorting stay bounded to 100-row pages. Search/category filtering
  happens on the server; column sorting is local to the displayed page.

## Build

```sh
cd iOS
xcodegen generate
xcodebuild -project ControllarrRemote.xcodeproj -scheme ControllarrRemote \
  -configuration Release -sdk iphonesimulator \
  -destination 'generic/platform=iOS Simulator' \
  -derivedDataPath /tmp/ControllarrRemoteBuild CODE_SIGNING_ALLOWED=NO build
```

Native Mac remote manager, including Apple Silicon and Intel:

```sh
xcodebuild -project ControllarrRemote.xcodeproj -scheme ControllarrRemoteMac \
  -configuration Release -destination 'generic/platform=macOS' \
  -derivedDataPath /tmp/ControllarrRemoteMacBuild ONLY_ACTIVE_ARCH=NO \
  CODE_SIGNING_ALLOWED=NO build
```

Public Mac binaries must be Developer ID signed and notarized. The command above
is for source compilation, not public distribution. The Mac remote manager uses
`com.controllarr.remote.mac` and does not replace the local torrent engine.

Host-only protocol tests, separate from simulator/device UI tests:

```sh
swift test --scratch-path /tmp/ControllarrRemoteProtocolBuild
```

Debug builds support `--layout-preview`: a disconnected 2,400-torrent library
with 100 loaded rows for safe layout checks. It cannot operate on a real server,
and fixture data/activation are excluded from Release builds.

For a physical device or TestFlight, select your valid Apple Developer team in
Xcode, use a registered bundle identifier, archive for iOS, then distribute
through App Store Connect. This preview does not include provisioning profiles,
private signing keys, APNs credentials or an installable public IPA. A simulator
build cannot run on an iPhone. The publisher has created valid Apple certificates,
the explicit App ID, an App Store provisioning profile and the App Store Connect
record. The distribution-signed archive passes signature validation with
`get-task-allow=false`. Universal device build 1.1.0 (3) was delivered through
Apple Transporter on October 8, 2026, processed by Apple and enabled in the
publisher's internal TestFlight testing group on October 9. Public TestFlight access is not available yet; do not treat the
simulator download as a phone installer.

Publisher upload options are in `ExportOptions-AppStore.plist`; other developers
must substitute their own team/profile. See [release signing](../docs/RELEASING.md).
Mac publishing uses `ExportOptions-DeveloperID.plist` and a matching Developer ID
profile authorizing the app's private Keychain access group. Profiles and private
keys are not included in the repository.
Distribution builds must use an Apple-supported release/RC Xcode and SDK, even
when the build Mac runs a beta macOS. The project declares all four iPad
orientations for multitasking, and the iOS icon is opaque RGB rather than the
transparent macOS artwork. Run `Scripts/check-release.swift` against the archived
device `.app` before exporting or uploading. Apple's Transporter can deliver an
exported App Store Connect-signed IPA if Xcode account lookup fails.

Passwords use the app's private Keychain without requiring user-presence
authentication. They are not included in project files or backups of instance
metadata. HTTP is opt-in; HTTPS uses normal certificate validation and rejects
redirects. Server hostnames can include an HTTPS reverse-proxy base path.
Mac uses its sandboxed data-protection Keychain, not a shared legacy login item.
Profiles are local to each platform; they are not synced through iCloud.

Local notifications use foreground polling and best-effort background refresh.
Mac polling continues while the app is running in the background, and stops
when it quits. This is explicitly not a reliable APNs push implementation.
