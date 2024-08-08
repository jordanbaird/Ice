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
            "The following applications failed to quit and were not restarted:\n" + failedApps.joined(separator: "\n")
        }

        var recoverySuggestion: String? {
            "You may need to log out for the changes to take effect."
        }
    }

    /// The offset to apply to the default spacing and padding.
    /// Does not take effect until ``applyOffset()`` is called.
    var offset = 0

    /// The wait time before force terminating an app.
    private let waitTimeBeforeForceTerminate: UInt64 = 3_000_000_000 // 3 seconds in nanoseconds

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

    /// Asynchronously signals the given app to quit.
    private func signalAppToQuit(_ app: NSRunningApplication) async throws {
        Logger.spacing.debug("Signaling application \"\(app.localizedName ?? "<NIL>")\" to quit")
        app.terminate()
        var cancellable: AnyCancellable?
        return try await withCheckedThrowingContinuation { continuation in
            let timeoutTask = Task {
                try await Task.sleep(nanoseconds: self.waitTimeBeforeForceTerminate)
                if !app.isTerminated {
                    Logger.spacing.debug("Application \"\(app.localizedName ?? "<NIL>")\" did not terminate within \(self.waitTimeBeforeForceTerminate / 1_000_000_000) seconds, attempting to force terminate")
                    app.forceTerminate()
                }
            }

            cancellable = app.publisher(for: \.isTerminated).sink { isTerminated in
                if isTerminated {
                    timeoutTask.cancel()
                    cancellable?.cancel()
                    Logger.spacing.debug("Application \"\(app.localizedName ?? "<NIL>")\" terminated successfully")
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
        struct RelaunchError: Error {}
        guard
            let url = app.bundleURL,
            let bundleIdentifier = app.bundleIdentifier
        else {
            throw RelaunchError()
        }
        try await signalAppToQuit(app)
        try? await Task.sleep(for: .nanoseconds(waitTimeBeforeForceTerminate))
        if app.isTerminated {
            try await launchApp(at: url, bundleIdentifier: bundleIdentifier)
        } else {
            throw RelaunchError()
        }
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
        var tasks = [Task<Void, Never>]()

        for pid in pids {
            guard
                let app = NSRunningApplication(processIdentifier: pid),
                // ControlCenter handles its own relaunch, so skip it
                app.bundleIdentifier != "com.apple.controlcenter",
                app != .current
            else {
                continue
            }
            tasks.append(Task {
                do {
                    try await self.relaunchApp(app)
                } catch {
                    if let name = app.localizedName {
                        failedApps.append(name)
                    }
                }
            })
        }

        // Wait for all tasks to complete
        for task in tasks {
            await task.value
        }

        try? await Task.sleep(for: .milliseconds(100))

        if let app = NSRunningApplication.runningApplications(withBundleIdentifier: "com.apple.controlcenter").first {
            do {
                try await signalAppToQuit(app)
                try? await Task.sleep(for: .nanoseconds(waitTimeBeforeForceTerminate))
                if !app.isTerminated {
                    if let name = app.localizedName {
                        failedApps.append(name)
                    }
                }
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
