# Operations Guide

This doc covers the first operator-focused v1.5 foundations that now exist on `main`.

## Headless Daemon

Controllarr can now run without the macOS app bundle:

```sh
swift run ControllarrDaemon --webui-root WebUI/dist
```

Useful flags:

- `--state-dir /path/to/state` to override the default Application Support location
- `--host 0.0.0.0` to override the configured bind host for the current run
- `--port 8791` to override the configured bind port for the current run

Notes:

- The daemon uses the same persistence store, HTTP API, and WebUI bundle as the desktop app.
- If `WebUI/dist` cannot be found, the daemon still runs in API-only mode.
- `Ctrl-C` triggers a clean shutdown so the current listen port and state are flushed.
- For LAN access from another machine, bind the WebUI to `0.0.0.0`, restart Controllarr, and connect to the Mac's LAN IP instead of `127.0.0.1`.

## Remote Access and VPN Diagnostics

Controllarr now includes a built-in network diagnostics panel in both the native Settings view and the WebUI Settings tab.

### What It Shows

- the current WebUI/API bind host and port
- the local URL the Mac itself should open
- detected private LAN IPs on the Mac
- the currently detected VPN interface and IP
- whether torrent traffic is bound to the VPN adapter
- a recommended LAN URL for Sonarr, Radarr, Overseerr, or another browser on your network

### How To Use It

- Bind the WebUI to `0.0.0.0` or a specific LAN IP such as `192.168.1.122`
- Save settings and restart Controllarr so the HTTP server rebinds
- Point remote clients at the recommended LAN URL, not `127.0.0.1` and not `0.0.0.0`

### VPN Caveat

- Controllarr already keeps torrent traffic on the VPN adapter separately from the WebUI/API listener
- If diagnostics say remote access is configured correctly but other machines still cannot connect while the VPN is on, the VPN client is likely blocking inbound LAN traffic at the OS/filter level

## Backup, Export, and Restore

The WebUI Settings tab now includes a **Backup & restore** panel.

### Export

- Use **Export backup** to download the current Controllarr state as JSON.
- Turn on **Include Keychain secrets in exports** if you want the backup to carry the WebUI password and saved *arr API keys.
- A redacted export is still useful for categories, save-path routing, seeding policy, health settings, and other non-secret state.

### Import

- Choose a previously exported JSON file and click **Import backup**.
- Import replaces the current persisted settings and categories with the backup contents.
- If the imported backup changes the WebUI bind host or port, Controllarr will warn that a restart is recommended.

### Current Limitations

- A backup exported without secrets is not a full machine-to-machine credential migration.
- Host and port changes are restored into persisted settings, but the current HTTP server keeps its existing bind until restart.
- Backup/restore is focused on persisted operator state; it is not yet a full historical analytics export.

## Recovery Rules and Recovery Center

Controllarr now includes a first-pass health-based recovery engine.

### What It Can Do

- Match active health issues such as metadata timeouts, no-peer stalls, stalled torrents with peers, and awaiting-recheck states
- Apply one automatic action per configured reason:
  - `reannounce`
  - `pause`
  - `remove_keep_files`
  - `remove_delete_files`
- Keep a rolling log of both automatic and manual recovery attempts in the WebUI Recovery tab

### How To Configure It

- Open the WebUI Settings tab and scroll to **Recovery rules**
- Add one or more rules with:
  - health reason
  - action
  - delay in minutes
  - enabled/disabled state
- Only the first enabled rule for a given reason is applied automatically

### Manual Recovery

- The Health tab now includes **Recover now** for active issues
- Manual recovery uses the configured rule for that health reason when one exists
- If no rule exists yet, Controllarr falls back to a one-off `reannounce`

### Current Limitations

- This is the first rule-engine slice, not the full playbook system from the roadmap
- Recovery rules currently focus on health issues only; they do not yet react to disk pressure, import failures, or tracker-specific policies
- Automatic runs are de-duplicated while the same issue remains active, then become eligible again if the issue clears and later returns

## Post-Processor Retry Queue

The WebUI Post-Processor tab is no longer read-only.

### What It Can Do

- Show move and extraction records for completed torrents
- Flag failed records as retryable
- Queue a manual retry that re-enters the post-processing pipeline for that torrent

### How To Use It

- Open the WebUI **Post-Processor** tab
- Find a row with a failed stage
- Click **Retry** to move the record back to `pending` and immediately re-evaluate the torrent

### Current Limitations

- Retry currently targets failed records only; successful rows are informational
- The retry path reuses the current category settings, so changed save paths or extraction toggles affect the next run
- If the torrent is no longer loaded in the session, the retry request is rejected

## Disk Space Monitor Operations

The WebUI Settings tab now exposes a more complete disk-space status card.

### What It Shows

- The path currently being monitored
- Current free space and the active threshold
- Whether downloads are paused by the monitor
- Which torrent hashes were paused by the monitor
- How much space is still needed before downloads can safely resume

### Operator Recheck

- Use **Recheck now** after freeing space or changing the configured threshold
- The recheck triggers an immediate monitor evaluation instead of waiting for the normal 30-second loop
- If free space is back above threshold, Controllarr resumes the torrents it paused
