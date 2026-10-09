# Controllarr Remote 1.1.0

A shared native remote workspace for iPhone, iPad, and Mac. This is a remote
manager for Controllarr v2.3.0+ servers, not a replacement torrent-engine app.

## Adaptive Interface

- Compact iPhone and narrow iPad windows use four tabs and touch-friendly rows.
- Larger iPad windows and Mac get a sidebar, sortable torrent table and inspector.
- The dashboard expands into a command grid with meaningful shortcuts, live
  session metrics and side-by-side recent activity.
- Search, category filters, current section and selection survive layout changes.
- Multi-selection supports pause, resume, category changes and confirmed removal,
  with separate keep-files and delete-files choices on the selected server.
- Mac includes native menus, context actions, Delete confirmation and keyboard
  shortcuts. Settings, categories, diagnostics and optional alerts remain shared.
- Server-filtered 100-row pages keep client memory and table work bounded.
  Column sorting applies to the displayed page, not the entire server library.

## Install

**Mac:** download `ControllarrRemote-v1.1.0-macOS-universal.zip`, unzip and move
`ControllarrRemote.app` to Applications. Requires macOS 15+; includes Apple Silicon
and Intel. Developer ID signed, Apple notarized and stapled. No self-signing or
quarantine-removal command is needed. Normal first-launch and network permission
prompts can still appear. Saved passwords use the app's private data-protection
Keychain, authorized by its embedded Apple profile. Mac Remote updates are manual.

**iPhone/iPad:** requires iOS/iPadOS 17+. Build 1.1.0 (3) is processed and active in
the existing internal TestFlight group. Install through TestFlight. There is no
public invitation link or App Store release yet; simulator packages do not install
on a physical iPhone.

Your existing Mac or Windows server, torrent storage and server updater are not
replaced by this release. Profiles are local to each device, not iCloud-synced.

## Checks and Limits

Ten host tests, iOS simulator compilation/headless launch, iOS distribution
preflight, Transporter processing, Mac universal compilation, signing,
notarization, Gatekeeper, re-extracted archive verification and disposable
Keychain save/load/update/delete checks passed. Native Mac fixture checks covered
dashboard, torrent table, inspector and selection across a window resize.

Physical-device rotation, iPad multitasking and Intel runtime have not been
fully exercised. iOS background alerts remain best-effort, not reliable APNs
push; Mac local alerts require Remote to stay running. This release does not
claim to diagnose earlier whole-system server crashes or finish Mac engine
feature parity. See `docs/REMOTE_VALIDATION_1.1.0.md` for the validation scope.
