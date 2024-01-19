//
//  UpdatesManager.swift
//  Ice
//

import Sparkle
import SwiftUI

final class UpdatesManager: ObservableObject {
    @Published var canCheckForUpdates = false

    let updaterController: SPUStandardUpdaterController

    var updater: SPUUpdater {
        updaterController.updater
    }

    init() {
        self.updaterController = SPUStandardUpdaterController(
            startingUpdater: true,
            updaterDelegate: nil,
            userDriverDelegate: nil
        )
        configureCancellables()
    }

    private func configureCancellables() {
        updater.publisher(for: \.canCheckForUpdates)
            .assign(to: &$canCheckForUpdates)
    }

    @objc func checkForUpdates() {
        #if DEBUG
        // checking for updates hangs in debug mode
        let alert = NSAlert()
        alert.messageText = "Checking for updates is not supported in debug mode."
        alert.runModal()
        #else
        updater.checkForUpdates()
        #endif
    }
}
