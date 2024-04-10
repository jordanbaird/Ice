//
//  AppDelegate.swift
//  Ice
//

import SwiftUI

@MainActor
class AppDelegate: NSObject, NSApplicationDelegate {
    let appState = AppState.shared

    func applicationDidFinishLaunching(_: Notification) {
        // assign the delegate to the shared app state
        appState.assignAppDelegate(self)

        // assign the settings window to the shared app state
        if let settingsWindow = NSApp.window(withIdentifier: Constants.settingsWindowID) {
            appState.assignSettingsWindow(settingsWindow)
            // give the settings window a custom background
            settingsWindow.backgroundColor = .settingsWindowBackground
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

    func applicationSupportsSecureRestorableState(_: NSApplication) -> Bool {
        return true
    }

    func applicationShouldTerminateAfterLastWindowClosed(_: NSApplication) -> Bool {
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
