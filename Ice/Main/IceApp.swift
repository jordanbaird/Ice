//
//  IceApp.swift
//  Ice
//

import SwiftUI

@main
struct IceApp: App {
    @NSApplicationDelegateAdaptor var appDelegate: AppDelegate
    @ObservedObject var appState = AppState()

    init() {
        appDelegate.assignAppState(appState)
        // ponytail: migration touches UserDefaults + SettingsManager; defer past
        // first paint so login-window boot isn't blocked on disk decode.
        let state = appState
        DispatchQueue.main.async {
            MigrationManager.migrateAll(appState: state)
        }
    }

    var body: some Scene {
        SettingsWindow(appState: appState)
        PermissionsWindow(appState: appState)
    }
}
