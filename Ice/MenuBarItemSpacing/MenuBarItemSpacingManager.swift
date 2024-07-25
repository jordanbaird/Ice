//
//  MenuBarItemSpacingManager.swift
//  Ice
//

import Cocoa
import Combine
import OSLog

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

    /// An error that groups multiple failed app relaunches.
    private struct GroupedRelaunchError: LocalizedError {
        let failedApps: [String]

        var errorDescription: String? {
            "The following applications failed to relaunch:\n" + failedApps.joined(separator: "\n")
        }

        var recoverySuggestion: String? {
            "You may need to log out for the changes to take effect."
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

    /// Asynchronously quits the given app.
    private func quitApp(_ app: NSRunningApplication) async throws {
        try await runCommand("kill", with: [String(app.processIdentifier)])
        var cancellable: AnyCancellable?
        return try await withCheckedThrowingContinuation { continuation in
            cancellable = app.publisher(for: \.isTerminated).sink { isTerminated in
                if isTerminated {
                    cancellable?.cancel()
                    continuation.resume()
                }
            }
        }
    }

    /// Asynchronously launches the app at the given URL.
    private func launchApp(at applicationURL: URL, bundleIdentifier: String) async throws {
        if let app = NSWorkspace.shared.runningApplications.first(where: { $0.bundleIdentifier == bundleIdentifier }) {
            Logger.spacing.debug("Application \"\(app.localizedName ?? "<NIL>")\" is already open, so skipping launch")
            return
        }
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.activates = false
        configuration.addsToRecentItems = false
        configuration.createsNewApplicationInstance = false
        configuration.promptsUserIfNeeded = false
        try await NSWorkspace.shared.openApplication(at: applicationURL, configuration: configuration)
    }

    /// Asynchronously relaunches the given app.
    private func relaunchApp(_ app: NSRunningApplication) async throws {
        struct RelaunchError: Error { }
        guard
            let url = app.bundleURL,
            let bundleIdentifier = app.bundleIdentifier
        else {
            throw RelaunchError()
        }
        try await quitApp(app)
        try? await Task.sleep(for: .milliseconds(50))
        try await launchApp(at: url, bundleIdentifier: bundleIdentifier)
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

        try? await Task.sleep(for: .milliseconds(100))

        let items = MenuBarItem.getMenuBarItemsPrivateAPI(onScreenOnly: false, activeSpaceOnly: true)
        let pids = Set(items.map { $0.ownerPID })

        var failedApps = [String]()

        for pid in pids {
            guard
                let app = NSRunningApplication(processIdentifier: pid),
                // ControlCenter handles its own relaunch, so quit it separately
                app.bundleIdentifier != "com.apple.controlcenter",
                app != .current
            else {
                continue
            }
            do {
                try await relaunchApp(app)
            } catch {
                if let name = app.localizedName {
                    failedApps.append(name)
                }
            }
        }

        try? await Task.sleep(for: .milliseconds(100))

        if let app = NSRunningApplication.runningApplications(withBundleIdentifier: "com.apple.controlcenter").first {
            do {
                try await quitApp(app)
            } catch {
                if let name = app.localizedName {
                    failedApps.append(name)
                }
            }
        }

        if !failedApps.isEmpty {
            throw GroupedRelaunchError(failedApps: failedApps)
        }
    }
}

private extension Logger {
    static let spacing = Logger(category: "Spacing")
}
