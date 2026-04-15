//
//  AppDelegate.swift
//  Controllarr — Phase 2
//
//  Regular-app AppDelegate. Installs an NSStatusItem as a convenience
//  menu-bar surface, waits for the SwiftUI ContentView to boot the
//  shared RuntimeViewModel, and shuts the runtime down on quit.
//

import AppKit
import SwiftUI
import ControllarrCore

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {

    private var statusItem: NSStatusItem?
    private var statsTimer: Timer?

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
            Task { @MainActor [weak self] in self?.rebuildMenu() }
        }
    }

    private func rebuildMenu() {
        statusItem?.menu = buildMenu()
    }

    private func buildMenu() -> NSMenu {
        let vm = RuntimeViewModel.shared
        let s = vm.session
        let title: String
        if vm.isBooting {
            title = "Starting…"
        } else {
            title = "Port \(s.listenPort) · \(s.numTorrents) torrents · ↓\(formatRate(s.downloadRate)) ↑\(formatRate(s.uploadRate))"
        }

        let menu = NSMenu()
        menu.autoenablesItems = false

        let statusLine = NSMenuItem(title: title, action: nil, keyEquivalent: "")
        statusLine.isEnabled = false
        menu.addItem(statusLine)

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
