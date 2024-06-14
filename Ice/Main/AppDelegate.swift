//
//  AppDelegate.swift
//  Ice
//

import OSLog
import SwiftUI

@MainActor
class AppDelegate: NSObject, NSApplicationDelegate {
    private var appState: AppState?

    func applicationWillFinishLaunching(_ notification: Notification) {
        guard let appState else {
            Logger.appDelegate.warning("\(#function) missing app state")
            return
        }

        // assign the delegate to the shared app state
        appState.assignAppDelegate(self)

        // allow the app to set the cursor in the background
        appState.setsCursorInBackground = true

        // set up the shared screen state manager
        ScreenStateManager.setUpSharedManager()
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        guard let appState else {
            Logger.appDelegate.warning("\(#function) missing app state")
            return
        }

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
        if
            let appState,
            appState.permissionsManager.hasPermission
        {
            appState.deactivate(withPolicy: .accessory)
            return false
        }
        return true
    }

    /// Assigns the app state to the delegate.
    func assignAppState(_ appState: AppState) {
        guard self.appState == nil else {
            Logger.appDelegate.warning("Multiple attempts made to assign app state")
            return
        }
        self.appState = appState
    }

    /// Opens the settings window and activates the app.
    @objc func openSettingsWindow() {
        guard
            let appState,
            let settingsWindow = appState.settingsWindow
        else {
            Logger.appDelegate.warning("Failed to open settings window")
            return
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            appState.activate(withPolicy: .regular)
            settingsWindow.center()
            settingsWindow.makeKeyAndOrderFront(self)
        }
    }
}

// MARK: - Logger
private extension Logger {
    static let appDelegate = Logger(category: "AppDelegate")
}
