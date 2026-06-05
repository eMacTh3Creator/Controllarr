//
//  UpdateManager.swift
//  Controllarr
//
//  Thin Sparkle facade. Keeps update scheduling policy in one place while
//  the persisted Settings model remains Sparkle-free.
//

import Foundation
import Sparkle
import Persistence

@MainActor
final class UpdateManager {
    static let shared = UpdateManager()

    private let updaterController: SPUStandardUpdaterController

    var updater: SPUUpdater { updaterController.updater }

    private init() {
        updaterController = SPUStandardUpdaterController(
            startingUpdater: true,
            updaterDelegate: nil,
            userDriverDelegate: nil
        )
    }

    func apply(settings: Persistence.Settings) {
        let checksEnabled = settings.uiPreferences.automaticUpdateChecks
        if updater.automaticallyChecksForUpdates != checksEnabled {
            updater.automaticallyChecksForUpdates = checksEnabled
        }
        if Int(updater.updateCheckInterval) != 604_800 {
            updater.updateCheckInterval = 604_800
        }
        if updater.automaticallyDownloadsUpdates {
            updater.automaticallyDownloadsUpdates = false
        }
    }
}
