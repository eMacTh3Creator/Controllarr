# v2.1.12 — Home dashboard, torrent search, smoother scrolling

This release focuses on the native app experience.

## Added

- **Home dashboard.** A new default Home tab mirrors the browser WebUI: a hero
  header with a live status pill, session metric cards (download/upload rate,
  torrents, active, peers, listen port, session totals), a status row
  (incoming / VPN / disk / health), quick actions, and a "Most Active"
  transfers list. Color language matches the WebUI accent palette.
- **Torrent search.** The Torrents tab now has a search box that filters by
  name, category, or info-hash as you type, with an inline clear button.
- **Clear to neutral.** A "Clear" control resets search and the status/category
  filters back to showing everything in one click; it only appears when a
  filter is active.

## Improved

- **Large-library scrolling.** The torrent list now computes its filtered and
  sorted rows once per update instead of several times, and each row uses a
  lightweight progress bar in place of the heavier stock control. Combined
  with search (fewer visible rows), the list stays smoother on 300+ torrent
  libraries refreshing every two seconds.

## Notes

- The Home dashboard and Torrents list read the same 2-second snapshot the rest
  of the app uses, so everything stays live without extra polling.
