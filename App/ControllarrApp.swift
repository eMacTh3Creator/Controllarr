//
//  ControllarrApp.swift
//  Controllarr — Phase 2
//
//  SwiftUI entry point. Regular dock-icon app with a main window and a
//  menu-bar status item. ControllarrRuntime lives inside
//  RuntimeViewModel.shared so both surfaces read the same source of
//  truth.
//

import SwiftUI
import AppKit
import ControllarrCore

@main
struct ControllarrApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    var body: some Scene {
        WindowGroup("Controllarr") {
            ContentView()
        }
        .windowResizability(.contentMinSize)
        .commands {
            CommandGroup(replacing: .newItem) {}
        }
    }
}
