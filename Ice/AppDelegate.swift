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

        // hide the main menu so that the user has more space to work with when
        // configuring their menu bar layout
        if let mainMenu = NSApp.mainMenu {
            for item in mainMenu.items {
                item.isHidden = true
            }
        }

        // initialize the status bar ONLY IF we aren't running in a SwiftUI preview;
        // otherwise, a new set of control items would be added every time the
        // preview reloads, and since Xcode doesn't seem to be very good at cleaning
        // up its old previews, the old items could stick around, too
        if !ProcessInfo.processInfo.isPreview {
            StatusBar.shared.initializeControlItems()
        }

        // make some adjustments to the window that can't be done in SwiftUI
        if let settingsWindow {
            settingsWindow.isMovableByWindowBackground = true
            settingsWindow.backgroundColor = NSColor(named: "SettingsWindowBackgroundColor")

            settingsWindow.titlebarAppearsTransparent = true
            settingsWindow.titleVisibility = .hidden

            let titleTextField = NSTextField(labelWithString: settingsWindow.title)
            titleTextField.textColor = .secondaryLabelColor
            titleTextField.font = .titleBarFont(ofSize: 0)
            titleTextField.alignment = .center

            let titleContainer = NSView()
            titleContainer.addSubview(titleTextField)

            titleTextField.translatesAutoresizingMaskIntoConstraints = false
            let xConstraint = titleTextField.centerXAnchor.constraint(equalTo: titleContainer.centerXAnchor)
            let yConstraint = titleTextField.centerYAnchor.constraint(equalTo: titleContainer.centerYAnchor)
            NSLayoutConstraint.activate([xConstraint, yConstraint])

            let titleController = NSTitlebarAccessoryViewController()
            titleController.view = titleContainer
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
