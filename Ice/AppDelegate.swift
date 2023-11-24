//
//  AppDelegate.swift
//  Ice
//

import SwiftUI

class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        if let settingsWindow = NSApp.window(withIdentifier: Constants.settingsWindowID) {
            AppState.shared.assignSettingsWindow(settingsWindow)
            // give the settings window a custom background
            settingsWindow.backgroundColor = .settingsWindowBackground
        }

        // close all windows
        for window in NSApp.windows {
            window.close()
        }

        // hide the main menu to make more space in the menu bar
        if let mainMenu = NSApp.mainMenu {
            for item in mainMenu.items {
                item.isHidden = true
            }
        }

        // initialize the menu bar's sections
        if !AppState.shared.isPreview {
            AppState.shared.menuBar.initializeSections()
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
    ///
    /// The app will automatically deactivate once all of its windows are closed.
    @objc func openSettingsWindow() {
        guard let settingsWindow = AppState.shared.settingsWindow else {
            return
        }
        activate(withPolicy: .regular)
        settingsWindow.center()
        settingsWindow.makeKeyAndOrderFront(self)
    }
}
