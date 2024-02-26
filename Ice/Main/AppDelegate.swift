//
//  AppDelegate.swift
//  Ice
//

import SwiftUI

class AppDelegate: NSObject, NSApplicationDelegate {
    let appState = AppState.shared

    func applicationDidFinishLaunching(_ notification: Notification) {
        // assign the delegate to the shared app state
        appState.assignAppDelegate(self)

        // assign the settings window to the shared app state
        if let settingsWindow = NSApp.window(withIdentifier: Constants.settingsWindowID) {
            appState.assignSettingsWindow(settingsWindow)
            // give the settings window a custom background
            settingsWindow.backgroundColor = .settingsWindowBackground
        }

        // close all windows
        for window in NSApp.windows {
            window.close()
        }

        if !appState.isPreview {
            // if we have the required permissions, stop all checks
            // and set up the menu bar
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
            deactivate(withPolicy: .accessory)
            return false
        }
        return true
    }

    /// Activates the app and sets its activation policy to the given value.
    func activate(withPolicy policy: NSApplication.ActivationPolicy) {
        if let frontApp = NSWorkspace.shared.frontmostApplication {
            NSRunningApplication.current.activate(from: frontApp)
        } else {
            NSApp.activate()
        }
        NSApp.setActivationPolicy(policy)
    }

    /// Deactivates the app and sets its activation policy to the given value.
    func deactivate(withPolicy policy: NSApplication.ActivationPolicy) {
        if let nextApp = NSWorkspace.shared.runningApplications.first(where: { $0 != .current }) {
            NSApp.yieldActivation(to: nextApp)
        } else {
            NSApp.deactivate()
        }
        NSApp.setActivationPolicy(policy)
    }

    /// Opens the settings window and activates the app.
    @objc func openSettingsWindow() {
        guard let settingsWindow = appState.settingsWindow else {
            return
        }
        activate(withPolicy: .regular)
        settingsWindow.center()
        settingsWindow.makeKeyAndOrderFront(self)
    }
}
