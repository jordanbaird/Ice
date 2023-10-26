//
//  PermissionsRequest.swift
//  Ice
//

import Cocoa

// MARK: - PermissionsRequest

protocol PermissionsRequest {
    /// The URL to the Settings pane where the user can grant the
    /// required permissions.
    var settingsPaneURL: URL? { get }

    /// Initializes an empty request.
    init()

    /// Performs the request.
    func perform()
}

extension PermissionsRequest {
    /// Opens the Settings pane associated with the request so that
    /// the user can grant the required permissions.
    func openSettingsPane() {
        guard let settingsPaneURL else {
            return
        }

        NSWorkspace.shared.open(settingsPaneURL)

        // if the Settings app is already running, the pane
        // might open without activating, so do it manually

        let settingsApp = NSWorkspace.shared.runningApplications.first { app in
            app.bundleIdentifier == "com.apple.systempreferences"
        }

        if #available(macOS 14.0, *) {
            settingsApp?.activate(from: .current)
        } else {
            settingsApp?.activate(options: .activateIgnoringOtherApps)
        }
    }
}

// MARK: - AccessibilityRequest
struct AccessibilityRequest: PermissionsRequest {
    var settingsPaneURL: URL? {
        URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")
    }

    func perform() {
        let dummyEvent = CGEvent(source: nil)
        dummyEvent?.post(tap: .cghidEventTap)
    }
}

// MARK: - ScreenCaptureRequest
struct ScreenCaptureRequest: PermissionsRequest {
    var settingsPaneURL: URL? {
        URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture")
    }

    func perform() {
        CGRequestScreenCaptureAccess()
    }
}
