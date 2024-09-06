//
//  AppDelegate.swift
//  Ice
//

import OSLog
import SwiftUI

@MainActor
class AppDelegate: NSObject, NSApplicationDelegate {
    private weak var appState: AppState?

    // MARK: NSApplicationDelegate Methods

    func applicationWillFinishLaunching(_ notification: Notification) {
        guard let appState else {
            Logger.appDelegate.warning("Missing app state in applicationWillFinishLaunching")
            return
        }

        // Assign the delegate to the shared app state.
        appState.assignAppDelegate(self)

        // Allow the app to set the cursor in the background.
        appState.setsCursorInBackground = true

        // Set up the shared screen state manager.
        ScreenStateManager.setUpSharedManager()
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        guard let appState else {
            Logger.appDelegate.warning("Missing app state in applicationDidFinishLaunching")
            return
        }

        // Assign and close the various windows.
        let windowAssignments: KeyValuePairs = [
            Constants.settingsWindowID: appState.assignSettingsWindow,
            Constants.permissionsWindowID: appState.assignPermissionsWindow,
        ]
        for (identifier, assign) in windowAssignments {
            if let window = NSApp.window(withIdentifier: identifier) {
                assign(window)
                window.close()
            }
        }

        // Hide the main menu to make more space in the menu bar.
        if let mainMenu = NSApp.mainMenu {
            for item in mainMenu.items {
                item.isHidden = true
            }
        }

        if !appState.isPreview {
            // If we have the required permissions, set up the shared app state.
            // Otherwise, open the permissions window.
            if appState.permissionsManager.hasPermission {
                appState.performSetup()
            } else if let permissionsWindow = appState.permissionsWindow {
                appState.activate(withPolicy: .regular)
                permissionsWindow.center()
                permissionsWindow.makeKeyAndOrderFront(nil)
            } else {
                Logger.appDelegate.error("Failed to open permissions window")
            }
        }
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        // Deactivate and set the policy to accessory when all windows are closed.
        appState?.deactivate(withPolicy: .accessory)
        return false
    }

    func applicationSupportsSecureRestorableState(_ app: NSApplication) -> Bool {
        return true
    }

    // MARK: Other Methods

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
        // Small delay makes this more reliable.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            appState.activate(withPolicy: .regular)
            settingsWindow.center()
            settingsWindow.makeKeyAndOrderFront(nil)
        }
    }
}

// MARK: - Logger
private extension Logger {
    static let appDelegate = Logger(category: "AppDelegate")
}
