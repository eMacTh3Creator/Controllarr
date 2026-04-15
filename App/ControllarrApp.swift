//
//  ControllarrApp.swift
//  Controllarr — Phase 1
//
//  SwiftUI entry point. The app runs as a pure menu-bar accessory:
//  no dock icon, no main window. The actual UI is the React WebUI
//  served by the embedded HTTP server — this file just owns the
//  menu-bar lifecycle and shells out to the default browser when the
//  user picks "Open Web UI".
//

import SwiftUI
import AppKit
import ControllarrCore
import Persistence
import PortWatcher
import TorrentEngine

@main
struct ControllarrApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    var body: some Scene {
        Settings {
            // No settings window in Phase 1 — all config lives in the
            // web UI. A SwiftUI settings pane lands in Phase 6.
            EmptyView()
        }
    }
}
