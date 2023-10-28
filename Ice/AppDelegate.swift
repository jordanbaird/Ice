//
//  AppDelegate.swift
//  Ice
//

import SwiftUI

class AppDelegate: NSObject, NSApplicationDelegate {
    /// Central app state.
    let appState = AppState()

    /// The window that contains the settings interface.
    var settingsWindow: NSWindow? {
        NSApp.window(withIdentifier: Constants.settingsWindowID)
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        // if we have the required permissions, stop all checks
        // and close all windows
        if appState.permissionsManager.hasPermissions {
            appState.permissionsManager.stopAllChecks()
            for window in NSApp.windows {
                window.close()
            }
        }

        // hide the main menu to make more space in the menu bar
        if let mainMenu = NSApp.mainMenu {
            for item in mainMenu.items {
                item.isHidden = true
            }
        }

        // give the settings window a custom background
        if let settingsWindow {
            settingsWindow.backgroundColor = .settingsWindowBackground
        }

        // initialize the menu bar's sections
        if !ProcessInfo.processInfo.isPreview {
            appState.menuBarManager.initializeSections()
        }
    }

    func applicationSupportsSecureRestorableState(_ app: NSApplication) -> Bool {
        return true
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        deactivate(withPolicy: .accessory)
        return false
    }

    /// Activates the app and sets its activation policy to the given value.
    func activate(withPolicy policy: NSApplication.ActivationPolicy) {
        if #available(macOS 14.0, *) {
            if let app = NSWorkspace.shared.frontmostApplication {
                NSRunningApplication.current.activate(from: app)
            } else {
                NSApp.activate()
            }
        } else {
            NSApp.activate(ignoringOtherApps: true)
        }
        NSApp.setActivationPolicy(policy)
        appState.sharedContent.activate()
    }

    /// Deactivates the app and sets its activation policy to the given value.
    func deactivate(withPolicy policy: NSApplication.ActivationPolicy) {
        lazy var nextApp = NSWorkspace.shared.runningApplications.first { app in
            app != .current
        }
        if
            #available(macOS 14.0, *),
            let nextApp
        {
            NSApp.yieldActivation(to: nextApp)
        } else {
            NSApp.deactivate()
        }
        NSApp.setActivationPolicy(policy)
        appState.sharedContent.deactivate()
    }

    /// Opens the settings window and activates the app.
    ///
    /// The app will automatically deactivate once all of its windows are closed.
    @objc func openSettingsWindow() {
        guard let settingsWindow else {
            return
        }
        activate(withPolicy: .regular)
        settingsWindow.center()
        settingsWindow.makeKeyAndOrderFront(self)
    }
}
