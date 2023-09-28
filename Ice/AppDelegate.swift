//
//  AppDelegate.swift
//  Ice
//

import SwiftUI

class AppDelegate: NSObject, NSApplicationDelegate {
    /// The window that contains the settings interface.
    private var settingsWindow: NSWindow? {
        NSApp.window(withIdentifier: Constants.settingsWindowID)
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
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

        // give the settings window a custom background
        if let settingsWindow {
            settingsWindow.backgroundColor = .settingsWindowBackground
        }
    }

    func applicationSupportsSecureRestorableState(_ app: NSApplication) -> Bool {
        return true
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        deactivate(withPolicy: .accessory)
        return false
    }

    /// Deactivates the app and sets its activation policy to the given value.
    private func deactivate(withPolicy policy: NSApplication.ActivationPolicy) {
        if #available(macOS 14.0, *) {
            // FIXME: Seems like there should be a better way to simply deactivate and yield
            // to the next available app, but I'm not seeing one. Yielding to an empty bundle
            // id is probably a bad (or at least not good) solution, but calling deactivate()
            // on macOS 14 causes the app to be unfocused the next time it activates
            NSApp.yieldActivation(toApplicationWithBundleIdentifier: "")
        } else {
            NSApp.deactivate()
        }
        NSApp.setActivationPolicy(policy)
        WindowList.shared.deactivate()
    }

    /// Opens the settings window and activates the app.
    ///
    /// The app will automatically deactivate once all of its windows are closed.
    @objc func openSettingsWindow() {
        guard let settingsWindow else {
            return
        }
        if #available(macOS 14.0, *) {
            NSApp.activate()
        } else {
            NSApp.activate(ignoringOtherApps: true)
        }
        NSApp.setActivationPolicy(.regular)
        settingsWindow.center()
        settingsWindow.makeKeyAndOrderFront(self)
        WindowList.shared.activate()
    }
}
