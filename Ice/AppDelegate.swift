//
//  AppDelegate.swift
//  Ice
//

import Combine
import SwiftUI

class AppDelegate: NSObject, NSApplicationDelegate {
    /// Observers that manage the key state of the delegate.
    private var cancellables = Set<AnyCancellable>()

    /// A Boolean value that indicates whether the delegate is allowed
    /// to deactivate the app.
    private var canDeactivateApp = true

    /// Toolbar to use as a replacement for the default SwiftUI toolbar
    /// in the settings window.
    private let replacementToolbar = NSToolbar()

    /// The window that contains the settings interface.
    private var settingsWindow: NSWindow? {
        NSApp.window(withIdentifier: Constants.settingsWindowID)
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        // close all windows
        for window in NSApp.windows {
            window.close()
        }

        // hide the main menu to give the user more space to configure their menu bar
        if let mainMenu = NSApp.mainMenu {
            for item in mainMenu.items {
                item.isHidden = true
            }
        }

        // make some adjustments to the window that can't be done in SwiftUI
        if let settingsWindow {
            settingsWindow.backgroundColor = NSColor(named: "SettingsWindowBackgroundColor")

            // SwiftUI seems to constantly try to update the toolbar, so listen for
            // changes and make sure our toolbar is used instead
            settingsWindow.publisher(for: \.toolbar)
                .sink { [weak self, weak settingsWindow] toolbar in
                    if toolbar !== self?.replacementToolbar {
                        settingsWindow?.toolbar = self?.replacementToolbar
                    }
                }
                .store(in: &cancellables)
        }
    }

    func applicationSupportsSecureRestorableState(_ app: NSApplication) -> Bool {
        return true
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        deactivate(sender, withPolicy: .accessory)
        return false
    }

    /// Deactivates the specified app instance and sets its activation
    /// policy to the given value.
    ///
    /// - Parameters:
    ///   - app: The app instance to deactivate.
    ///   - policy: The activation policy to switch to.
    ///
    /// - Returns: `true` if the policy switch succeeded; otherwise `false`.
    @discardableResult
    private func deactivate(
        _ app: NSApplication,
        withPolicy policy: NSApplication.ActivationPolicy
    ) -> Bool {
        guard canDeactivateApp else {
            return false
        }
        return app.deactivate(withPolicy: policy)
    }

    /// Opens the settings window and activates the app.
    ///
    /// The app will automatically deactivate once all of its windows
    /// are closed.
    @objc func openSettingsWindow() {
        guard let settingsWindow else {
            return
        }
        // if this is the first time the app is activated, the window needs a chance
        // to perform some initial layout, which, unfortunately, is visible to the user
        // if the window is ordered to the front at the same time as app activation;
        // the workaround is to activate the app and wait until the next run loop pass
        // to order the window to the front

        // since opening the window is being delayed, don't allow the delegate to
        // deactivate the app until it finishes
        canDeactivateApp = false

        NSApp.activate(withPolicy: .regular)

        DispatchQueue.main.async {
            settingsWindow.center()
            settingsWindow.makeKeyAndOrderFront(self)
            self.canDeactivateApp = true
        }
    }
}
