# Performance Guide

This document covers the v1.3 performance and scaling work that landed for Controllarr.

## Goals

The target for v1.3 was straightforward:

- keep Controllarr responsive with very large libraries, including 1,000+ torrents
- use available CPU cores when there is genuinely parallel work to do
- avoid turning the app into a memory or background-CPU hog just because the UI or API is open

That does not mean every workload will be identical. A library with 1,000 mostly idle torrents is very different from 1,000 actively changing torrents on a slow disk. The work in v1.3 is about reducing Controllarr's own overhead so libtorrent, disk I/O, and the network become the real bottlenecks.

## What Changed in v1.3

### Shared Torrent Snapshot Cache

The `TorrentEngine` now caches a short-lived torrent snapshot and derives session totals from that same pass. This collapses several back-to-back libtorrent scans into one shared snapshot when the runtime loop, HTTP API, WebUI, and native UI all ask for state around the same time.

### Single-Pass Session Aggregation

Session totals such as download rate, upload rate, peer count, and torrent count are now derived from the cached torrent snapshot instead of triggering a second scan.

### Parallel Service Ticks

The runtime still performs one coordinated tick, but post-processing, seeding-policy checks, and health-monitor analysis now fan out concurrently after the shared torrent snapshot is collected. This improves multi-core utilization without duplicating polling work.

### Native UI Fast/Slow Refresh Split

The macOS window no longer republishes every actor snapshot every two seconds. Fast-changing state such as torrents, session totals, health issues, and VPN/disk status remains on the fast cadence. Slower operator state such as categories, logs, recovery history, and settings refreshes less aggressively.

The menu-bar status item was also changed to update its status line in place instead of rebuilding the whole menu every cycle.

### WebUI Active-Tab Polling

The browser UI used to fetch nearly every table on every 2-second refresh. It now always refreshes the live torrent/session summary, then fetches only the active tab's heavier data set during normal live polling. Full refreshes still load everything when needed.

### Conservative libtorrent Thread Tuning

The libtorrent session now uses a balanced `aio_threads` budget based on available cores, keeps hashing threads conservative, and increases the alert queue size to reduce alert drops under load. The intention is better throughput and less backpressure, not aggressive maximum-resource operation.

## Practical Guidance

If you want the best results on large libraries:

- run the Release build or the published app when testing scale
- use the daemon mode for always-on servers when the native window is not needed
- leave detailed peer/tracker views for active troubleshooting rather than permanent monitoring
- avoid keeping noisy log views open on multiple browser sessions unless you need them
- keep completed media on reasonably fast local storage when possible

## What To Watch

If you are validating a big migration or a 1,000+ torrent environment, check:

- CPU in Activity Monitor while the app is idle versus while torrents are actively changing
- memory growth over time with the window open and with browser sessions connected
- responsiveness of the Torrents tab and API under normal polling
- whether disk pressure or VPN rules introduce secondary pauses that look like performance issues

## Current Boundaries

v1.3 removes a lot of avoidable overhead, but there are still some workload-dependent limits:

- tracker and peer detail views are intentionally on-demand and still do real work for the selected torrent
- very large browser sessions will still pay the cost of rendering large tables
- storage speed and tracker/peer churn can dominate the total cost once Controllarr's own polling overhead is reduced

If you hit a real-world scaling wall after v1.3, the next step should be profiling on that workload rather than guessing. Use Instruments, Activity Monitor, and the app's own logs to identify whether the hot path is SwiftUI invalidation, WebUI rendering, libtorrent polling, or disk/network behavior.
