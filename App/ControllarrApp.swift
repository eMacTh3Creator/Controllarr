//
//  ControllarrApp.swift
//  Controllarr — v1.0
//
//  SwiftUI entry point. Regular dock-icon app with a main window and a
//  menu-bar status item. ControllarrRuntime lives inside
//  RuntimeViewModel.shared so both surfaces read the same source of
//  truth. Sparkle handles automatic updates via the appcast.
//

import SwiftUI
import AppKit
import ControllarrCore
import Sparkle

@main
struct ControllarrApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    private let updaterController: SPUStandardUpdaterController

    init() {
        updaterController = SPUStandardUpdaterController(
            startingUpdater: true,
            updaterDelegate: nil,
            userDriverDelegate: nil
        )
    }

    var body: some Scene {
        WindowGroup("Controllarr") {
            ContentView()
        }
        .windowResizability(.contentMinSize)
        .commands {
            CommandGroup(replacing: .newItem) {}
            CommandGroup(after: .appInfo) {
                CheckForUpdatesView(updater: updaterController.updater)
            }
        }
    }
}
