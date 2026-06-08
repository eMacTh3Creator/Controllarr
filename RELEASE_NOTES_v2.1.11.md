# v2.1.11 — Hardened libtorrent DNS resolver (large-library insurance)

This release embeds a locally built, defensively hardened copy of
libtorrent 2.0.12 aimed at the DNS resolver path implicated in large-library
crash reports.

## Changed

- The shipped app now embeds a patched libtorrent 2.0.12 that makes
  `libtorrent::aux::resolver::on_lookup` re-entrancy-safe: pending resolve
  callbacks are extracted and erased from the internal map, and the resolved
  address list is copied out, **before** any callback is invoked — so no
  iterators or cache references are held across user callbacks.
- The patch and a reproducible build script live in the repo
  (`patches/libtorrent-2.0.12-resolver-reentrancy.patch`,
  `scripts/build-patched-libtorrent.sh`). The build links the ABI-identical
  Homebrew libtorrent and only the embedded runtime copy changes.

## Honest scope

This is **defense-in-depth, not a confirmed root-cause fix.** The exact
`on_lookup` code is unchanged across all current upstream libtorrent branches
(master, RC_2_0, RC_1_2), and in libtorrent's single-network-thread model the
original code is already memory-safe — so this hardening has no demonstrable
behavioral difference under normal operation. The large-library crash that was
reported (with the Mac rebooting) is more consistent with resource exhaustion
at scale or an out-of-process cause than a deterministic resolver logic bug.

The resolver-pressure mitigations from v2.1.9/v2.1.10 (conservative caps with
hysteresis, slowed mass reannounce, leaner polling) remain the primary
large-library protections. If you run hundreds of active torrents, keep those
in place and continue to watch logs after upgrading.

## Verified

- Patched libtorrent builds, links, exports the resolver symbol, and runs a
  live session in an isolated smoke test.
- The shipped app embeds the patched code (verified by `__TEXT` section hash,
  distinct from the stock Homebrew dylib), passes `codesign --verify --deep
  --strict` through a `ditto` round-trip, and the full test suite passes.
