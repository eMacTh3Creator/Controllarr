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
final class AppDelegate: NSObject, NSApplicationDelegate {

    private var statusItem: NSStatusItem?
    private var statsTimer: Timer?
    private var statusLineItem: NSMenuItem?

    /// Files/URLs received before the runtime finishes booting.
    /// Drained once RuntimeViewModel.isBooting becomes false.
    private var pendingTorrentFiles: [URL] = []
    private var pendingMagnetURIs: [String] = []

    nonisolated func applicationDidFinishLaunching(_ notification: Notification) {
        MainActor.assumeIsolated {
            NSApp.setActivationPolicy(.regular)
            installStatusItem()
            startStatusRefresh()
        }
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
        NSApp.activate(ignoringOtherApps: true)
        for window in NSApp.windows where window.canBecomeMain {
            window.makeKeyAndOrderFront(nil)
            return
        }
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
        NSApp.activate(ignoringOtherApps: true)
        for window in NSApp.windows where window.canBecomeMain {
            window.makeKeyAndOrderFront(nil)
            return
        }
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
        NSApp.activate(ignoringOtherApps: true)
        for window in NSApp.windows where window.canBecomeMain {
            window.makeKeyAndOrderFront(nil)
            return
        }
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
