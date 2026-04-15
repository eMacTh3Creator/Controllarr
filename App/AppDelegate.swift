//
//  AppDelegate.swift
//  Controllarr — Phase 1
//
//  Owns the NSStatusItem menu-bar UI, boots ControllarrRuntime, and
//  shuts it down cleanly on quit. Everything here runs on the main
//  actor — AppKit APIs require it, and it keeps the Swift 6 strict
//  concurrency story simple.
//

import AppKit
import SwiftUI
import ControllarrCore
import Persistence

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {

    private var statusItem: NSStatusItem?
    private var runtime: ControllarrRuntime?
    private var statsTimer: Timer?
    private var latestStatus: StatusLine = .starting

    enum StatusLine {
        case starting
        case running(port: Int, torrents: Int, dlRate: Int64, upRate: Int64)
        case stopped

        var menuTitle: String {
            switch self {
            case .starting: return "Starting…"
            case .stopped:  return "Stopped"
            case .running(let port, let n, let d, let u):
                return "Port \(port) · \(n) torrents · ↓\(fmt(d)) ↑\(fmt(u))"
            }
        }

        private func fmt(_ bps: Int64) -> String {
            let kb = Double(bps) / 1024
            if kb < 1024 { return String(format: "%.0f KiB/s", kb) }
            return String(format: "%.1f MiB/s", kb / 1024)
        }
    }

    // MARK: - Lifecycle

    nonisolated func applicationDidFinishLaunching(_ notification: Notification) {
        MainActor.assumeIsolated {
            NSApp.setActivationPolicy(.accessory)
            installStatusItem()
            Task { await self.bootRuntime() }
        }
    }

    nonisolated func applicationWillTerminate(_ notification: Notification) {
        MainActor.assumeIsolated {
            statsTimer?.invalidate()
            statsTimer = nil
            let runtime = self.runtime
            let sema = DispatchSemaphore(value: 0)
            Task.detached {
                await runtime?.shutdown()
                sema.signal()
            }
            _ = sema.wait(timeout: .now() + 5)
        }
    }

    // MARK: - Runtime

    private func bootRuntime() async {
        // The React build output (`WebUI/dist`) is copied into the .app as
        // `Contents/Resources/dist` by xcodegen's folder-reference source.
        let webUIRoot = Bundle.main.url(forResource: "dist", withExtension: nil)
        let runtime = await ControllarrRuntime(webUIRoot: webUIRoot)
        self.runtime = runtime
        do {
            try await runtime.start()
        } catch {
            NSLog("[Controllarr] runtime start failed: \(error)")
        }
        startStatsPolling()
    }

    private func startStatsPolling() {
        statsTimer?.invalidate()
        statsTimer = Timer.scheduledTimer(withTimeInterval: 2.0, repeats: true) { [weak self] _ in
            // Timer callback fires on main thread; hop onto MainActor
            // isolation explicitly so the strict concurrency checker
            // is satisfied.
            Task { @MainActor [weak self] in
                await self?.refreshStatus()
            }
        }
        Task { [weak self] in await self?.refreshStatus() }
    }

    private func refreshStatus() async {
        guard let runtime = runtime else { return }
        let s = await runtime.engine.sessionStats()
        latestStatus = .running(
            port: Int(s.listenPort),
            torrents: s.numTorrents,
            dlRate: s.downloadRate,
            upRate: s.uploadRate
        )
        rebuildMenu()
    }

    // MARK: - Menu

    private func installStatusItem() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        if let button = item.button {
            let image = NSImage(
                systemSymbolName: "arrow.up.arrow.down.circle",
                accessibilityDescription: "Controllarr"
            )
            image?.isTemplate = true
            button.image = image
        }
        item.menu = buildMenu()
        self.statusItem = item
    }

    private func rebuildMenu() {
        statusItem?.menu = buildMenu()
    }

    private func buildMenu() -> NSMenu {
        let menu = NSMenu()
        menu.autoenablesItems = false

        let statusLine = NSMenuItem(title: latestStatus.menuTitle, action: nil, keyEquivalent: "")
        statusLine.isEnabled = false
        menu.addItem(statusLine)

        menu.addItem(.separator())

        let openWeb = NSMenuItem(
            title: "Open Web UI",
            action: #selector(openWebUI),
            keyEquivalent: "o"
        )
        openWeb.target = self
        menu.addItem(openWeb)

        let cycle = NSMenuItem(
            title: "Cycle Listen Port Now",
            action: #selector(cyclePort),
            keyEquivalent: ""
        )
        cycle.target = self
        menu.addItem(cycle)

        menu.addItem(.separator())

        let quit = NSMenuItem(
            title: "Quit Controllarr",
            action: #selector(quit),
            keyEquivalent: "q"
        )
        quit.target = self
        menu.addItem(quit)

        return menu
    }

    // MARK: - Actions

    @objc private func openWebUI() {
        Task { [weak self] in
            guard let self, let runtime = self.runtime else { return }
            let settings = await runtime.store.settings()
            if let url = URL(string: "http://\(settings.webUIHost):\(settings.webUIPort)/") {
                await MainActor.run { NSWorkspace.shared.open(url) }
            }
        }
    }

    @objc private func cyclePort() {
        Task { [weak self] in
            guard let self, let runtime = self.runtime else { return }
            await runtime.portWatcher.forceCycle(reason: "menu bar")
        }
    }

    @objc private func quit() {
        NSApp.terminate(nil)
    }
}
