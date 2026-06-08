# v2.1.13 — Critical launch-crash fix

**If you are on v2.1.11 or v2.1.12, update to this build.** Those two releases
crash at launch on any Mac without Homebrew's libtorrent installed:

```
Library not loaded: /opt/homebrew/.../libtorrent-rasterbar.2.0.dylib
Termination Reason: DYLD, Library missing
```

## What happened

v2.1.11 introduced embedding a locally built libtorrent. That change broke the
bundling step that rewrites library paths to be self-contained: the app's main
binary kept an **absolute `/opt/homebrew` path** for libtorrent (and the
embedded OpenSSL kept an absolute path to libcrypto). On a build machine with
Homebrew present the app still launched — but it loaded Homebrew's libtorrent
instead of the embedded one, and on any clean machine it crashed at launch
because that path does not exist.

## Fixed

- The bundling step now reads each binary's **actual** library references and
  rewrites every `/opt/homebrew` path to an in-bundle `@rpath`, regardless of
  Homebrew's `opt/` vs versioned `Cellar/` layout.
- Added a **hard self-containment gate**: the build now fails if any binary in
  the app still references `/opt/homebrew`, so this class of bug can never ship
  again.
- Verified at runtime (via dyld) that the app loads the embedded libraries and
  launches on a machine without Homebrew.

A side effect: the hardened libtorrent from v2.1.11 is now actually the copy
that loads at runtime (previously the app was loading Homebrew's copy where it
ran at all).

## Note

All the v2.1.12 app features — the Home dashboard, torrent search, clear-to-
neutral, and the scrolling work — are included here. This release adds the
launch-crash fix on top.
