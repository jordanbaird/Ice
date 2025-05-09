//
//  IceApp.swift
//  Ice
//

import SwiftUI

@main
struct IceApp: App {
    @NSApplicationDelegateAdaptor var appDelegate: AppDelegate

    init() {
        NSSplitViewItem.swizzle()
        MigrationManager.migrateAll(appState: AppState.shared)
        appDelegate.assignAppState(AppState.shared)
    }

    var body: some Scene {
        SettingsWindow(appState: AppState.shared)
        PermissionsWindow(appState: AppState.shared)
    }
}
