//
//  MenuBarItemSpacingManager.swift
//  Ice
//

import Cocoa
import Combine

/// Manager for menu bar item spacing.
class MenuBarItemSpacingManager {
    /// UserDefaults keys.
    private enum Key: String {
        case spacing = "NSStatusItemSpacing"
        case padding = "NSStatusItemSelectionPadding"
    }

    /// The standard values for the keys.
    private enum StandardValues {
        static let spacing = 16
        static let padding = 16
    }

    enum AdjustSpacingError: LocalizedError {
        case quitAppFailed(String?)
        case launchAppFailed(String?)
        case restartAppFailed(String?)

        var errorDescription: String? {
            switch self {
            case .quitAppFailed(let app?):
                "Failed to quit \"\(app)\"."
            case .launchAppFailed(let app?):
                "Failed to launch \"\(app)\"."
            case .restartAppFailed(let app?):
                "Failed to restart \"\(app)\"."
            case .quitAppFailed:
                "Failed to quit application."
            case .launchAppFailed:
                "Failed to launch application."
            case .restartAppFailed:
                "Failed to restart application."
            }
        }

        var recoverySuggestion: String? {
            switch self {
            case .quitAppFailed, .restartAppFailed:
                "You may need to log out for the changes to take effect."
            case .launchAppFailed(.some):
                "You may need to manually launch the app."
            case .launchAppFailed:
                "The application does not provide its name. You may need to check which apps are open and manually launch the one that failed."
            }
        }
    }

    /// The offset to apply to the default spacing and padding.
    /// Does not take effect until ``applyOffset()`` is called.
    var offset = 0

    /// Runs a command with the given arguments.
    private func runCommand(_ command: String, with arguments: [String]) async throws {
        let process = Process()

        process.executableURL = URL(filePath: "/usr/bin/env")
        process.arguments = CollectionOfOne(command) + arguments

        let task = Task.detached {
            try process.run()
            process.waitUntilExit()
        }

        return try await task.value
    }

    /// Removes the value for the specified key.
    private func removeValue(forKey key: Key) async throws {
        try await runCommand("defaults", with: ["-currentHost", "delete", "-globalDomain", key.rawValue])
    }

    /// Sets the value for the specified key.
    private func setValue(_ value: Int, forKey key: Key) async throws {
        try await runCommand("defaults", with: ["-currentHost", "write", "-globalDomain", key.rawValue, "-int", String(value)])
    }

    /// Applies the current ``offset``.
    ///
    /// - Note: Calling this restarts all apps with a menu bar item.
    func applyOffset() async throws {
        if offset == 0 {
            try await removeValue(forKey: .spacing)
            try await removeValue(forKey: .padding)
        } else {
            try await setValue(StandardValues.spacing + offset, forKey: .spacing)
            try await setValue(StandardValues.padding + offset, forKey: .padding)
        }

        try await Task.sleep(for: .milliseconds(100))

        let items = MenuBarItem.getMenuBarItemsPrivateAPI(onScreenOnly: false, activeSpaceOnly: true)
        let pids = Set(items.map { $0.ownerPID })

        for pid in pids {
            guard
                let app = NSRunningApplication(processIdentifier: pid),
                let url = app.bundleURL,
                app != .current
            else {
                continue
            }
            try await runCommand("kill", with: [String(app.processIdentifier)])
            try await runCommand("open", with: ["-g", url.path()])
        }

        try await Task.sleep(for: .milliseconds(100))

        if let app = NSRunningApplication.runningApplications(withBundleIdentifier: "com.apple.controlcenter").first {
            try await runCommand("kill", with: [String(app.processIdentifier)])
        }
    }
}
