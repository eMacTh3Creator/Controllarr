# Controllarr v1.3.0

## Highlights

- Added a shared torrent snapshot cache in `TorrentEngine` so the runtime loop, API, WebUI, and native app can reuse one short-lived libtorrent scan instead of repeatedly walking the whole session
- Moved session total aggregation onto that same shared snapshot path, eliminating a second pass just to compute rates, peer counts, and torrent totals
- Parallelized the runtime's post-processing, seeding-policy, and health-monitor analysis after the shared snapshot is collected
- Split the native app into fast and slow refresh paths so high-churn data stays live without republishing categories, logs, and recovery history every 2 seconds
- Switched the WebUI to active-tab live polling so it no longer fetches every heavy table on every interval
- Tuned libtorrent with a balanced multi-core I/O thread budget and a larger alert queue to improve large-library behavior without making the client excessively hungry

## Operator Notes

- v1.3 is aimed at larger libraries and long-running nodes, especially environments with 1,000+ torrents
- For the cleanest scale testing, use the Release build or the published app rather than a Debug build
- Headless daemon mode remains the best fit for always-on servers where the native macOS window is not needed
- This release improves Controllarr's own overhead substantially, but absolute performance will still depend on storage speed, peer churn, tracker behavior, and how many torrents are actively changing at once

## Install Note

- The macOS build is ad-hoc signed. If Gatekeeper blocks launch after you move the app into `/Applications`, you can re-sign it locally and clear the quarantine flag:

```sh
codesign --force --deep --sign - "/Applications/Controllarr.app" \
  && xattr -rd com.apple.quarantine "/Applications/Controllarr.app"
```
