//
//  MenuBarItemSpacingManager.swift
//  Ice
//

import Cocoa
import Combine

/// Manager for menu bar item spacing.
@MainActor
final class MenuBarItemSpacingManager {
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
    struct GroupedRelaunchError: LocalizedError {
        let failedApps: [String]

        var errorDescription: String? {
            "The following applications failed to quit and were not restarted:\n" + failedApps.joined(separator: "\n")
        }

        var recoverySuggestion: String? {
            "You may need to log out for the changes to take effect."
        }
    }

    /// Delay before force terminating an app.
    private let forceTerminateDelay = 1

    /// The offset to apply to the default spacing and padding.
    /// Does not take effect until ``applyOffset()`` is called.
    var offset = 0

    /// Runs a command with the given arguments, throwing on non-zero exit.
    private func runCommand(_ command: String, with arguments: [String]) async throws {
        let process = Process()

        process.executableURL = URL(filePath: "/usr/bin/env")
        process.arguments = CollectionOfOne(command) + arguments

        let errorPipe = Pipe()
        process.standardError = errorPipe

        let task = Task.detached {
            try process.run()
            process.waitUntilExit()
        }

        try await task.value

        if process.terminationStatus != 0 {
            let rawMessage = String(data: errorPipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8)?
                .trimmingCharacters(in: .whitespacesAndNewlines)
            let message: String
            if let rawMessage, !rawMessage.isEmpty {
                message = rawMessage
            } else {
                message = "Command '\(command)' failed with exit code \(process.terminationStatus)"
            }
            throw NSError(
                domain: "MenuBarItemSpacing",
                code: Int(process.terminationStatus),
                userInfo: [NSLocalizedDescriptionKey: message]
            )
        }
    }

    /// Removes the value for the specified key. Missing keys are ignored
    /// so resetting to default never fails on a fresh system.
    private func removeValue(forKey key: Key) async throws {
        do {
            try await runCommand("defaults", with: ["-currentHost", "delete", "-globalDomain", key.rawValue])
        } catch {
            // ponytail: `defaults delete` exits 1 when the key was never set —
            // that's already the default state, not a failure.
            if (error as NSError).localizedDescription.lowercased().contains("does not exist") {
                return
            }
            throw error
        }
    }

    /// Sets the value for the specified key to the key's default value plus the given offset.
    private func setOffset(_ offset: Int, forKey key: Key) async throws {
        try await runCommand("defaults", with: ["-currentHost", "write", "-globalDomain", key.rawValue, "-int", String(key.defaultValue + offset)])
    }

    /// Returns a log string for the given app.
    private nonisolated func logString(for app: NSRunningApplication) -> String {
        app.localizedName ?? app.bundleIdentifier ?? "<NIL>"
    }

    /// Asynchronously signals the given app to quit.
    private func signalAppToQuit(_ app: NSRunningApplication) async throws {
        if app.isTerminated {
            Logger.spacing.debug("Application \"\(logString(for: app))\" is already terminated")
            return
        } else {
            Logger.spacing.debug("Signaling application \"\(logString(for: app))\" to quit")
        }

        app.terminate()

        var cancellable: AnyCancellable?
        return try await withCheckedThrowingContinuation { continuation in
            let timeoutTask = Task {
                try await Task.sleep(for: .seconds(forceTerminateDelay))
                if !app.isTerminated {
                    Logger.spacing.debug("Application \"\(logString(for: app))\" did not terminate within \(forceTerminateDelay) seconds, attempting to force terminate")
                    app.forceTerminate()
                }
            }

            cancellable = app.publisher(for: \.isTerminated).sink { [weak self] isTerminated in
                guard
                    let self,
                    isTerminated
                else {
                    return
                }
                timeoutTask.cancel()
                cancellable?.cancel()
                Logger.spacing.debug("Application \"\(logString(for: app))\" terminated successfully")
                continuation.resume()
            }
        }
    }

    /// Asynchronously launches the app at the given URL.
    private nonisolated func launchApp(at applicationURL: URL, bundleIdentifier: String) async throws {
        if let app = NSWorkspace.shared.runningApplications.first(where: { $0.bundleIdentifier == bundleIdentifier }) {
            Logger.spacing.debug("Application \"\(logString(for: app))\" is already open, so skipping launch")
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
        try await signalAppToQuit(app)
        if app.isTerminated {
            try await launchApp(at: url, bundleIdentifier: bundleIdentifier)
        } else {
            throw RelaunchError()
        }
    }

    /// Whether spacing changes require a logout to take effect.
    ///
    /// On macOS 26 and later the system reads `NSStatusItemSpacing` and
    /// `NSStatusItemSelectionPadding` at login time only — restarting menu
    /// bar apps, MenuBarAgent, or ControlCenter does not pick up new values
    /// (verified on macOS 27: icon positions identical after each restart).
    static var requiresLogoutToApply: Bool {
        ProcessInfo.processInfo.operatingSystemVersion.majorVersion >= 26
    }

    /// Applies the current ``offset``.
    ///
    /// - Note: On macOS 26 and later this only writes the preferences; the
    ///   user must log out for the changes to take effect. On earlier versions
    ///   this restarts all apps with a menu bar item.
    func applyOffset() async throws {
        if offset == 0 {
            try await removeValue(forKey: .spacing)
            try await removeValue(forKey: .padding)
        } else {
            try await setOffset(offset, forKey: .spacing)
            try await setOffset(offset, forKey: .padding)
        }

        // ponytail: no relaunch dance on macOS 26+ — prefs are login-time only,
        // so killing user apps would risk unsaved work for zero visual effect.
        guard !Self.requiresLogoutToApply else {
            return
        }

        try? await Task.sleep(for: .milliseconds(100))

        let items = MenuBarItem.getMenuBarItems(onScreenOnly: false, activeSpaceOnly: true)
        let pids = Set(items.map { $0.ownerPID })

        // Collect failed app names as task results instead of mutating a
        // shared array — avoids a data race across concurrent relaunch tasks.
        let failedFromRelaunch: [String] = await withTaskGroup(of: String?.self) { group in
            for pid in pids {
                guard
                    let app = NSRunningApplication(processIdentifier: pid),
                    app.bundleIdentifier != "com.apple.controlcenter", // ControlCenter handles its own relaunch, so skip it.
                    app != .current
                else {
                    continue
                }
                group.addTask { @MainActor in
                    do {
                        try await self.relaunchApp(app)
                        return nil
                    } catch {
                        guard let name = app.localizedName else {
                            return nil
                        }
                        if app.bundleIdentifier == "com.apple.Spotlight" {
                            // Spotlight automatically relaunches, so only consider it a failure if it never quit.
                            if
                                let latestSpotlightInstance = NSRunningApplication.runningApplications(withBundleIdentifier: "com.apple.Spotlight").first,
                                latestSpotlightInstance.processIdentifier == app.processIdentifier
                            {
                                return name
                            }
                            return nil
                        } else {
                            return name
                        }
                    }
                }
            }
            var collected = [String]()
            for await name in group {
                if let name {
                    collected.append(name)
                }
            }
            return collected
        }

        var failedApps = failedFromRelaunch

        try? await Task.sleep(for: .milliseconds(100))

        if let app = NSRunningApplication.runningApplications(withBundleIdentifier: "com.apple.controlcenter").first {
            do {
                try await signalAppToQuit(app)
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

// MARK: - Logger
private extension Logger {
    static let spacing = Logger(category: "Spacing")
}
