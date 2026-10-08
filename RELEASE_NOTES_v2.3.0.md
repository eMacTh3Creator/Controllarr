# v2.3.0 - Safer Mac Libraries, Import Paths and Remote Management

- Bulk libtorrent status retrieval avoids per-torrent status calls and piece-bitfield copies. Unchanged native snapshots are not republished.
- Resume saves queue up to 16 requests at once, drain alerts during normal operation and have a bounded shutdown wait. Folder metadata writes coalesce during mass intake.
- Native quit awaits shutdown without blocking the main actor on a semaphore; previous termination could time out before its main-actor cleanup ran. New intake inherits configured per-torrent connection/upload caps.
- The session starts network-paused until VPN policy is evaluated; protected disconnects gate new adds and force resumes. Port changes retain the selected binding.
- Archive extraction is limited to two workers, scoped to selected torrent files, and drains bounded stderr without pipe deadlock. Storage moves reject existing-file replacement.
- Category editors expose per-torrent subfolders. Existing categories retain their old policy; new categories default on. Trailing separators are not required.
- qBittorrent `contentLayout=Subfolder` is honored. `content_path` and logical `save_path` are distinct for owned content folders, correcting Sonarr's base-directory import warning.
- Native main/category tables support confirmed pause-first bulk removal and Delete-key choices. Explicit import-folder repair is available; no silent reorganization of existing payloads.
- Authenticated Remote Protocol 1 adds bounded torrent pages and a 512-event journal, optional LAN Bonjour discovery, move/recheck/reannounce controls and matching Windows support.
- Native iOS Remote 1.0 source/simulator preview supports instances, hostname/HTTPS setup, bulk torrent/category/settings management, priorities, diagnostics and notification choices. This is not an installable iPhone release or guaranteed background push.
- Packaging rejects embedded libraries requiring newer than macOS 15; includes compatible OpenSSL and preserves self-containment checks. The Mac app is Developer ID signed, Apple notarized and stapled; Gatekeeper assessment and ticket validation passed.

## Checks and Limits

57 Mac regression tests passed. A real libtorrent 1,000-paused-torrent fixture
completed intake/snapshot/checkpoint/removal/shutdown in about 0.65 seconds on
the build host; this is not live-transfer throughput or a soak test. Isolated
authenticated API smoke passed. iOS simulator build/launch and six host protocol
tests passed; simulator XCTest execution was blocked by Xcode device-service
attachment failure. No cause of the reported whole-Mac reboot is established
without panic/watchdog logs. Full advanced Windows parity and APNs/TestFlight
distribution remain documented in [PARITY.md](docs/PARITY.md).

The Sparkle feed uses the existing publisher key. Its Ed25519 signature and exact
archive length were independently verified against the embedded public key.
Installed apps do not access the publisher's private signing key.

## Install

Extract the Mac ZIP, move Controllarr.app to Applications and open it normally.
No self-signing or quarantine-removal workaround is required. macOS may show
its standard first-launch confirmation or network permission prompts.
Existing profiles/downloads are retained. Back up state before a large migration. Change
the default WebUI password before enabling LAN access. See [mobile setup](docs/MOBILE.md).
