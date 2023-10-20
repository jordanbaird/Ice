//
//  AppDelegate.swift
//  Ice
//

import SwiftUI

class AppDelegate: NSObject, NSApplicationDelegate {
    /// The shared menu bar manager.
    let menuBarManager = MenuBarManager()

    /// The window that contains the settings interface.
    var settingsWindow: NSWindow? {
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

        // initialize the menu bar's sections
        if !ProcessInfo.processInfo.isPreview {
            menuBarManager.initializeSections()
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
            NSApp.activate()
        } else {
            NSApp.activate(ignoringOtherApps: true)
        }
        NSApp.setActivationPolicy(policy)
        menuBarManager.sharedContent.activate()
    }

    /// Deactivates the app and sets its activation policy to the given value.
    func deactivate(withPolicy policy: NSApplication.ActivationPolicy) {
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
        menuBarManager.sharedContent.deactivate()
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
