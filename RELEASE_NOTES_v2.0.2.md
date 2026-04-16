# Controllarr v2.0.2

Two quality-of-life fixes.

## What's new

### Category filter on the Torrents tab

The Torrents table now has a category dropdown next to the status
dropdown. Options are:

- **All Categories** (default — no filtering)
- **Uncategorized** — torrents not assigned to any category
- **Every user-defined category** (e.g. `radarr`, `tv-sonarr`,
  `done-import`) pulled live from your category list

Selection is persisted across app restarts the same way the status
filter is — via `UIPreferences.torrentCategoryFilter` in
`state.json`. Re-launching restores the last choice.

The status and category filters compose — e.g. "Downloading" ×
"radarr" shows only actively downloading Radarr torrents.

### Menu-bar "Show Window" now actually works

Previously, closing the main window (red X) with close-to-menu-bar
turned on could leave the SwiftUI scene torn down, so subsequent
"Show Window" clicks from the menu-bar icon did nothing. Same story
for the start-minimized flow.

2.0.2 makes the whole menu-bar menu robust:

- The app now installs itself as the main window's `NSWindowDelegate`
  and intercepts `windowShouldClose`. When close-to-menu-bar is on,
  the window is hidden (`orderOut`) instead of destroyed, so the
  NSWindow instance stays around.
- The window is marked `isReleasedWhenClosed = false`, so even in
  edge cases where SwiftUI tries to tear it down, the instance
  survives.
- **Show Window** re-keys the cached window (deminiaturizing if
  needed), falls back to any `canBecomeMain` window in `NSApp.windows`,
  and as a last resort fires Cocoa's `newWindowForTab:` responder
  action which SwiftUI's `WindowGroup` catches and answers by
  opening a fresh window.
- **Start Minimized** now uses `orderOut(nil)` instead of `close()`
  for the same reason.

**Open Web UI**, **Cycle Listen Port Now**, and **Quit Controllarr**
were already correctly wired; they are verified end-to-end in this
release but no code changes were needed for them.

## Upgrade notes

Drop-in patch. `UIPreferences` gained one optional field
(`torrentCategoryFilter`); old `state.json` files decode cleanly with
the default "All Categories" selection.

No backend, persistence-schema, or libtorrent behavior changes.
