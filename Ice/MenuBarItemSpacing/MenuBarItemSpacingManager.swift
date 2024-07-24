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

        /// The default value for the key.
        var defaultValue: Int {
            switch self {
            case .spacing: 16
            case .padding: 16
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

    /// Sets the value for the specified key to the key's default value plus the given offset.
    private func setOffset(_ offset: Int, forKey key: Key) async throws {
        try await runCommand("defaults", with: ["-currentHost", "write", "-globalDomain", key.rawValue, "-int", String(key.defaultValue + offset)])
    }

    /// Quits the app with the given process identifier.
    private func quitApp(with pid: pid_t) async throws {
        try await runCommand("kill", with: [String(pid)])
    }

    /// Launches the app at the given URL.
    private func launchApp(at url: URL) async throws {
        try await runCommand("open", with: ["-g", url.path()])
    }

    /// Applies the current ``offset``.
    ///
    /// - Note: Calling this restarts all apps with a menu bar item.
    func applyOffset() async throws {
        if offset == 0 {
            try await removeValue(forKey: .spacing)
            try await removeValue(forKey: .padding)
        } else {
            try await setOffset(offset, forKey: .spacing)
            try await setOffset(offset, forKey: .padding)
        }

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
            try await quitApp(with: pid)
            try await launchApp(at: url)
        }

        if let app = NSRunningApplication.runningApplications(withBundleIdentifier: "com.apple.controlcenter").first {
            try await quitApp(with: app.processIdentifier)
        }
    }
}
