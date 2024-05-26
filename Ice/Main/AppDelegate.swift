//
//  AppDelegate.swift
//  Ice
//

import SwiftUI

@MainActor
class AppDelegate: NSObject, NSApplicationDelegate {
    let appState = AppState.shared

    func applicationWillFinishLaunching(_ notification: Notification) {
        // assign the delegate to the shared app state
        appState.assignAppDelegate(self)

        // set up the shared screen state manager
        ScreenStateManager.setUpSharedManager()
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        // assign the settings window to the shared app state
        if let settingsWindow = NSApp.window(withIdentifier: Constants.settingsWindowID) {
            appState.assignSettingsWindow(settingsWindow)
            settingsWindow.close()
        }

        // assign the permissions window to the shared app state
        if let permissionsWindow = NSApp.window(withIdentifier: Constants.permissionsWindowID) {
            appState.assignPermissionsWindow(permissionsWindow)
        }

        if !appState.isPreview {
            // if we have the required permissions, set up the
            // shared app state
            if appState.permissionsManager.hasPermission {
                appState.performSetup()
            }
        }

        // hide the main menu to make more space in the menu bar
        if let mainMenu = NSApp.mainMenu {
            for item in mainMenu.items {
                item.isHidden = true
            }
        }

        // hide all sections
        for section in appState.menuBarManager.sections {
            section.hide()
        }
    }

    func applicationSupportsSecureRestorableState(_ app: NSApplication) -> Bool {
        return true
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        if appState.permissionsManager.hasPermission {
            appState.deactivate(withPolicy: .accessory)
            return false
        }
        return true
    }

    /// Opens the settings window and activates the app.
    @objc func openSettingsWindow() {
        guard let settingsWindow = appState.settingsWindow else {
            return
        }
        appState.activate(withPolicy: .regular)
        settingsWindow.center()
        settingsWindow.makeKeyAndOrderFront(self)
    }
}
