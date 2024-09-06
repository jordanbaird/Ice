//
//  IceApp.swift
//  Ice
//

import SwiftUI

@main
struct IceApp: App {
    @NSApplicationDelegateAdaptor var appDelegate: AppDelegate
    @ObservedObject var appState = AppState()
    @Environment(\.openWindow) private var openWindow

    init() {
        NSSplitViewItem.swizzle()
        IceBarPanel.swizzle()
        // Occurs before AppDelegate.applicationWillFinishLaunching(_:).
        appDelegate.assignAppState(appState)
    }

    var body: some Scene {
        SettingsWindow(appState: appState, onAppear: {
            // Open the permissions window no matter what, so that we can
            // reference it. We'll close it in AppDelegate if permissions
            // have already been granted.
            openWindow(id: Constants.permissionsWindowID)
        })
        PermissionsWindow(appState: appState, onContinue: {
            appState.performSetup()
            openWindow(id: Constants.settingsWindowID)
        })
    }
}
