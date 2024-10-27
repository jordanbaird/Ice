//
//  AppDelegate.swift
//  Ice
//

import SwiftUI

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
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
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        guard let appState else {
            Logger.appDelegate.warning("Missing app state in applicationDidFinishLaunching")
            return
        }

        // Dismiss the windows.
        appState.dismissSettingsWindow()
        appState.dismissPermissionsWindow()

        // Hide the main menu to make more space in the menu bar.
        if let mainMenu = NSApp.mainMenu {
            for item in mainMenu.items {
                item.isHidden = true
            }
        }

        // Perform setup after a small delay to ensure that the settings window
        // has been assigned.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            guard !appState.isPreview else {
                return
            }
            // If we have the required permissions, set up the shared app state.
            // Otherwise, open the permissions window.
            switch appState.permissionsManager.permissionsState {
            case .hasAllPermissions, .hasRequiredPermissions:
                appState.performSetup()
            case .missingPermissions:
                appState.activate(withPolicy: .regular)
                appState.openPermissionsWindow()
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
        guard let appState else {
            Logger.appDelegate.error("Failed to open settings window")
            return
        }
        // Small delay makes this more reliable.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            appState.activate(withPolicy: .regular)
            appState.openSettingsWindow()
        }
    }
}

// MARK: - Logger
private extension Logger {
    static let appDelegate = Logger(category: "AppDelegate")
}
