//
//  AppDelegate.swift
//  Controllarr — v1.1
//
//  Regular-app AppDelegate. Installs an NSStatusItem as a convenience
//  menu-bar surface, handles .torrent file opens and magnet: URL scheme
//  from the OS, and shuts the runtime down on quit.
//

import AppKit
import SwiftUI
import ControllarrCore

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate {

    private var statusItem: NSStatusItem?
    private var statsTimer: Timer?
    private var statusLineItem: NSMenuItem?

    /// Cached reference to the SwiftUI main window. Captured once the
    /// scene installs it so `showWindow` can bring it back from any state
    /// (visible, ordered-out, miniaturized) without relying on
    /// `NSApp.windows` iteration — which can return an empty list after
    /// SwiftUI teardown on a red-X close.
    private weak var mainWindow: NSWindow?
    /// Previous delegate (SwiftUI's own) so we can forward unhandled
    /// messages and not break state restoration.
    private weak var forwardingWindowDelegate: NSWindowDelegate?
    private var windowAttached: Bool = false

    /// Files/URLs received before the runtime finishes booting.
    /// Drained once RuntimeViewModel.isBooting becomes false.
    private var pendingTorrentFiles: [URL] = []
    private var pendingMagnetURIs: [String] = []

    nonisolated func applicationDidFinishLaunching(_ notification: Notification) {
        MainActor.assumeIsolated {
            NSApp.setActivationPolicy(.regular)
            installStatusItem()
            startStatusRefresh()
            // Observe the runtime's settings once it finishes booting so we
            // can honor menu-bar preferences (hide status item, minimize on
            // launch, close-to-menu-bar).
            Task { @MainActor in
                while RuntimeViewModel.shared.isBooting {
                    try? await Task.sleep(nanoseconds: 200_000_000)
                }
                self.attachToMainWindow()
                self.applyInterfacePreferences()
            }
        }
    }

    /// Find the SwiftUI-managed main window, cache a reference to it,
    /// keep it retained across close events, and hook ourselves in as its
    /// delegate so we can intercept `windowShouldClose` for close-to-menu-bar.
    private func attachToMainWindow() {
        guard !windowAttached else { return }
        guard let window = NSApp.windows.first(where: { $0.canBecomeMain }) else { return }
        window.isReleasedWhenClosed = false
        forwardingWindowDelegate = window.delegate
        window.delegate = self
        mainWindow = window
        windowAttached = true
    }

    // MARK: - NSWindowDelegate

    nonisolated func windowShouldClose(_ sender: NSWindow) -> Bool {
        MainActor.assumeIsolated {
            let prefs = RuntimeViewModel.shared.settings.uiPreferences
            if prefs.menuBarEnabled && prefs.closeToMenuBar {
                // User wants close-to-menu-bar: hide rather than tear down
                // so `showWindow` can bring it straight back.
                sender.orderOut(nil)
                return false
            }
            if let forward = forwardingWindowDelegate,
               forward.responds(to: #selector(NSWindowDelegate.windowShouldClose(_:))),
               let answer = forward.windowShouldClose?(sender) {
                return answer
            }
            return true
        }
    }

    // We only override `windowShouldClose`; every other NSWindowDelegate
    // callback reaches SwiftUI through its own internal wiring (it uses
    // notification observers, not delegate dispatch, for scene lifecycle).

    /// Pull the current `UIPreferences` off the runtime and reconcile the
    /// live menu-bar state. Called on boot completion and every time the
    /// operator saves Settings — wired through `RuntimeViewModel.saveSettings`.
    func applyInterfacePreferences() {
        let prefs = RuntimeViewModel.shared.settings.uiPreferences

        // Menu-bar toggle — install or tear down the status item.
        if prefs.menuBarEnabled {
            if statusItem == nil { installStatusItem() }
        } else {
            if let item = statusItem {
                NSStatusBar.system.removeStatusItem(item)
                statusItem = nil
                statusLineItem = nil
            }
        }

        // Start minimized — hide the main window if requested and if the
        // menu-bar icon is the user's entry point back to the UI. Use
        // orderOut (not close) so SwiftUI keeps the NSWindow alive and
        // `showWindow` can re-key it later.
        if prefs.menuBarEnabled && prefs.startMinimized && !didHandleStartMinimized {
            didHandleStartMinimized = true
            if let window = mainWindow ?? NSApp.windows.first(where: { $0.canBecomeMain }) {
                window.orderOut(nil)
            }
        }
    }

    private var didHandleStartMinimized: Bool = false

    /// When `closeToMenuBar` is on and the menu-bar icon is available,
    /// closing the main window shouldn't quit the app.
    nonisolated func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        MainActor.assumeIsolated {
            let prefs = RuntimeViewModel.shared.settings.uiPreferences
            return !(prefs.menuBarEnabled && prefs.closeToMenuBar)
        }
    }

    /// Reopening the dock icon (or clicking Show Window from the menu bar)
    /// should bring the window back.
    nonisolated func applicationShouldHandleReopen(
        _ sender: NSApplication,
        hasVisibleWindows flag: Bool
    ) -> Bool {
        MainActor.assumeIsolated {
            if !flag {
                self.bringMainWindowForward()
                return false
            }
            return true
        }
    }

    /// Core logic shared by `showWindow` (menu-bar action) and
    /// `applicationShouldHandleReopen` (Dock-icon click). Tries the cached
    /// reference first; if SwiftUI has torn the window down completely,
    /// falls back to iterating `NSApp.windows`.
    private func bringMainWindowForward() {
        NSApp.activate(ignoringOtherApps: true)
        if let window = mainWindow {
            window.setIsVisible(true)
            if window.isMiniaturized { window.deminiaturize(nil) }
            window.makeKeyAndOrderFront(nil)
            return
        }
        for window in NSApp.windows where window.canBecomeMain {
            mainWindow = window
            window.isReleasedWhenClosed = false
            window.setIsVisible(true)
            if window.isMiniaturized { window.deminiaturize(nil) }
            window.makeKeyAndOrderFront(nil)
            return
        }
        // Nothing to re-key — SwiftUI destroyed the window entirely.
        // Ask the Cocoa responder chain to open a new one; SwiftUI
        // WindowGroup handles this via its `newWindowForTab:` fallback.
        NSApp.sendAction(Selector(("newWindowForTab:")), to: nil, from: nil)
    }

    nonisolated func applicationWillTerminate(_ notification: Notification) {
        MainActor.assumeIsolated {
            statsTimer?.invalidate()
            statsTimer = nil
        }
        let sema = DispatchSemaphore(value: 0)
        Task {
            await RuntimeViewModel.shared.shutdown()
            sema.signal()
        }
        _ = sema.wait(timeout: .now() + 5)
    }

    // MARK: - File open handling (.torrent files from Finder / double-click)

    nonisolated func application(_ sender: NSApplication, openFiles filenames: [String]) {
        MainActor.assumeIsolated {
            let torrentFiles = filenames
                .map { URL(fileURLWithPath: $0) }
                .filter { $0.pathExtension.lowercased() == "torrent" }

            guard !torrentFiles.isEmpty else {
                sender.reply(toOpenOrPrint: .failure)
                return
            }

            let vm = RuntimeViewModel.shared
            if vm.isBooting {
                pendingTorrentFiles.append(contentsOf: torrentFiles)
            } else {
                addTorrentFiles(torrentFiles)
            }
            sender.reply(toOpenOrPrint: .success)
        }
    }

    // MARK: - URL scheme handling (magnet: links)

    nonisolated func application(_ application: NSApplication, open urls: [URL]) {
        MainActor.assumeIsolated {
            for url in urls {
                if url.scheme?.lowercased() == "magnet" {
                    let magnetURI = url.absoluteString
                    let vm = RuntimeViewModel.shared
                    if vm.isBooting {
                        pendingMagnetURIs.append(magnetURI)
                    } else {
                        addMagnetURI(magnetURI)
                    }
                }
            }
        }
    }

    // MARK: - Deferred queue (process once runtime is ready)

    /// Called by RuntimeViewModel after boot completes.
    func drainPendingOpens() {
        if !pendingTorrentFiles.isEmpty {
            addTorrentFiles(pendingTorrentFiles)
            pendingTorrentFiles.removeAll()
        }
        if !pendingMagnetURIs.isEmpty {
            for uri in pendingMagnetURIs {
                addMagnetURI(uri)
            }
            pendingMagnetURIs.removeAll()
        }
    }

    private func addTorrentFiles(_ urls: [URL]) {
        let vm = RuntimeViewModel.shared
        for url in urls {
            Task {
                do {
                    try await vm.addTorrentFile(at: url, category: nil)
                } catch {
                    NSLog("[Controllarr] Failed to add .torrent file \(url.lastPathComponent): \(error)")
                }
            }
        }
        // Bring the window to front so the user sees the added torrent.
        bringMainWindowForward()
    }

    private func addMagnetURI(_ uri: String) {
        let vm = RuntimeViewModel.shared
        Task {
            do {
                try await vm.addMagnet(uri, category: nil)
            } catch {
                NSLog("[Controllarr] Failed to add magnet URI: \(error)")
            }
        }
        bringMainWindowForward()
    }

    // MARK: - Status menu

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

    private func startStatusRefresh() {
        statsTimer?.invalidate()
        statsTimer = Timer.scheduledTimer(withTimeInterval: 2.0, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in self?.refreshStatusLine() }
        }
    }

    private func refreshStatusLine() {
        statusLineItem?.title = statusTitle()
    }

    private func buildMenu() -> NSMenu {
        let menu = NSMenu()
        menu.autoenablesItems = false

        let statusLine = NSMenuItem(title: statusTitle(), action: nil, keyEquivalent: "")
        statusLine.isEnabled = false
        menu.addItem(statusLine)
        self.statusLineItem = statusLine

        menu.addItem(.separator())

        let show = NSMenuItem(title: "Show Window", action: #selector(showWindow), keyEquivalent: "0")
        show.target = self
        menu.addItem(show)

        let openWeb = NSMenuItem(title: "Open Web UI", action: #selector(openWebUI), keyEquivalent: "o")
        openWeb.target = self
        menu.addItem(openWeb)

        let cycle = NSMenuItem(title: "Cycle Listen Port Now", action: #selector(cyclePort), keyEquivalent: "")
        cycle.target = self
        menu.addItem(cycle)

        menu.addItem(.separator())

        let quit = NSMenuItem(title: "Quit Controllarr", action: #selector(quit), keyEquivalent: "q")
        quit.target = self
        menu.addItem(quit)

        return menu
    }

    private func statusTitle() -> String {
        let vm = RuntimeViewModel.shared
        let s = vm.session
        if vm.isBooting {
            return "Starting..."
        }
        return "Port \(s.listenPort) \u{00B7} \(s.numTorrents) torrents \u{00B7} \u{2193}\(formatRate(s.downloadRate)) \u{2191}\(formatRate(s.uploadRate))"
    }

    @objc private func showWindow() {
        bringMainWindowForward()
    }

    @objc private func openWebUI() {
        RuntimeViewModel.shared.openWebUI()
    }

    @objc private func cyclePort() {
        Task { await RuntimeViewModel.shared.cyclePort() }
    }

    @objc private func quit() {
        NSApp.terminate(nil)
    }
}
