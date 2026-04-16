//
//  CheckForUpdatesView.swift
//  Controllarr
//
//  SwiftUI wrapper around Sparkle's SPUUpdater for a "Check for Updates"
//  menu item. Uses a simple approach compatible with Swift 6 strict
//  concurrency — avoids key-path observation of main-actor-isolated
//  properties.
//

import SwiftUI
@preconcurrency import Sparkle

@MainActor
final class CheckForUpdatesViewModel: ObservableObject {
    @Published var canCheckForUpdates = false

    init(updater: SPUUpdater) {
        updater.publisher(for: \.canCheckForUpdates)
            .assign(to: &$canCheckForUpdates)
    }
}

struct CheckForUpdatesView: View {
    @ObservedObject private var viewModel: CheckForUpdatesViewModel
    private let updater: SPUUpdater

    init(updater: SPUUpdater) {
        self.updater = updater
        self.viewModel = CheckForUpdatesViewModel(updater: updater)
    }

    var body: some View {
        Button("Check for Updates…", action: updater.checkForUpdates)
            .disabled(!viewModel.canCheckForUpdates)
    }
}
