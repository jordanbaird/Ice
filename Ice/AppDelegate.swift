//
//  AppDelegate.swift
//  Ice
//

import Combine
import SwiftUI

class AppDelegate: NSObject, NSApplicationDelegate {
    private var cancellables = Set<AnyCancellable>()

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

            // hide the default titlebar
            settingsWindow.titlebarAppearsTransparent = true
            settingsWindow.titleVisibility = .hidden

            // create a custom text field for the title
            let titleTextField = NSTextField(labelWithString: settingsWindow.title)
            titleTextField.textColor = .secondaryLabelColor
            titleTextField.font = .titleBarFont(ofSize: 0)
            titleTextField.alignment = .center

            // changing the position of an accessory view breaks the layout; use
            // a separate container view as the accessory view, and position the
            // title text inside it
            let titleContainer = NSView()
            titleContainer.addSubview(titleTextField)

            titleTextField.translatesAutoresizingMaskIntoConstraints = false
            let xConstraint = titleTextField.centerXAnchor.constraint(equalTo: titleContainer.centerXAnchor)
            let yConstraint = titleTextField.centerYAnchor.constraint(equalTo: titleContainer.centerYAnchor)
            NSLayoutConstraint.activate([xConstraint, yConstraint])

            let titleController = NSTitlebarAccessoryViewController()
            titleController.view = titleContainer
            // place the accessory view above the (now hidden) title bar
            titleController.layoutAttribute = .top

            settingsWindow.addTitlebarAccessoryViewController(titleController)

            // the window buttons (close, minimize, zoom) prevent the title container
            // from taking the full width of the window; offset the text field by the
            // half the remaining space to center the title
            titleContainer.publisher(for: \.frame)
                .combineLatest(settingsWindow.publisher(for: \.frame))
                .sink { [weak xConstraint] containerFrame, windowFrame in
                    xConstraint?.constant = -(windowFrame.width - containerFrame.width) / 2
                }
                .store(in: &cancellables)

            // keep the text field up to date when the title changes
            settingsWindow.publisher(for: \.title)
                .sink { [weak titleTextField] title in
                    titleTextField?.stringValue = title
                }
                .store(in: &cancellables)
        }
    }

    func applicationSupportsSecureRestorableState(_ app: NSApplication) -> Bool {
        return true
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        sender.deactivate(withPolicy: .accessory)
        return false
    }

    @objc func openSettingsWindow() {
        guard let settingsWindow else {
            return
        }
        NSApp.activate(withPolicy: .regular)
        settingsWindow.center()
        settingsWindow.makeKeyAndOrderFront(self)
    }
}
