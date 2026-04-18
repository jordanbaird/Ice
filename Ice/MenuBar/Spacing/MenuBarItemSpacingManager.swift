//
//  MenuBarItemSpacingManager.swift
//  Ice
//

import Cocoa
import Combine
import OSLog
import os.lock

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
    private struct GroupedRelaunchError: LocalizedError {
        let failedApps: [String]

        var errorDescription: String? {
            "The following applications failed to quit and were not restarted:\n" + failedApps.joined(separator: "\n")
        }

        var recoverySuggestion: String? {
            "You may need to log out for the changes to take effect."
        }
    }

    /// Logger for the menu bar item spacing manager.
    private let logger = Logger(category: "MenuBarItemSpacingManager")

    /// Delay before force terminating an app.
    private let forceTerminateDelay = 1

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

    /// Asynchronously signals the given app to quit.
    private func signalAppToQuit(_ app: NSRunningApplication) async throws {
        if app.isTerminated {
            logger.debug("Application \"\(app.logString, privacy: .public)\" is already terminated")
            return
        } else {
            logger.debug("Signaling application \"\(app.logString, privacy: .public)\" to quit")
        }

        app.terminate()

        var cancellable: AnyCancellable?
        let didResume = OSAllocatedUnfairLock(initialState: false)
        return try await withCheckedThrowingContinuation { continuation in
            let timeoutTask = Task {
                try await Task.sleep(for: .seconds(forceTerminateDelay))
                if !app.isTerminated {
                    logger.debug(
                        """
                        Application \"\(app.logString, privacy: .public)\" did not terminate within \
                        \(self.forceTerminateDelay, privacy: .public) seconds, attempting to force terminate
                        """
                    )
                    app.forceTerminate()
                    // Failsafe: if KVO doesn't fire after force terminate, resume anyway.
                    try? await Task.sleep(for: .seconds(1))
                    cancellable?.cancel()
                    if didResume.tryClaimOnce() {
                        continuation.resume()
                    }
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
                logger.debug("Application \"\(app.logString, privacy: .public)\" terminated successfully")
                if didResume.tryClaimOnce() {
                    continuation.resume()
                }
            }
        }
    }

    /// Asynchronously launches the app at the given URL.
    ///
    /// `replacedPID` is the PID of the just-terminated process. The
    /// "already running" check ignores any process matching that PID,
    /// so an auto-respawn under a new PID is recognized as fresh,
    /// while an unexpected match against the dead PID falls through to
    /// `openApplication(at:)`.
    private nonisolated func launchApp(at applicationURL: URL, bundleIdentifier: String, replacedPID: pid_t) async throws {
        if let app = NSWorkspace.shared.runningApplications.first(where: {
            $0.bundleIdentifier == bundleIdentifier && $0.processIdentifier != replacedPID
        }) {
            logger.debug("Application \"\(app.logString, privacy: .public)\" already running at PID \(app.processIdentifier, privacy: .public), skipping launch")
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
        let oldPID = app.processIdentifier
        try await signalAppToQuit(app)
        if app.isTerminated {
            try await launchApp(at: url, bundleIdentifier: bundleIdentifier, replacedPID: oldPID)
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

        let items = await MenuBarItem.getMenuBarItems(option: .activeSpace)
        let pids = Set(items.map { $0.sourcePID ?? $0.ownerPID })
        logger.debug("applyOffset: \(items.count, privacy: .public) items, \(pids.count, privacy: .public) unique PIDs: \(pids.map { String($0) }.sorted().joined(separator: ", "), privacy: .public)")

        var failedApps = [String]()

        await withTaskGroup(of: Void.self) { group in
            for pid in pids {
                guard let app = NSRunningApplication(processIdentifier: pid) else {
                    logger.debug("applyOffset: skipping pid \(pid, privacy: .public) (no NSRunningApplication)")
                    continue
                }
                guard app.bundleIdentifier != "com.apple.controlcenter" else {
                    logger.debug("applyOffset: skipping pid \(pid, privacy: .public) (Control Center)")
                    continue
                }
                guard app != .current else {
                    logger.debug("applyOffset: skipping pid \(pid, privacy: .public) (self)")
                    continue
                }
                logger.debug("applyOffset: relaunching pid \(pid, privacy: .public) bundle=\(app.bundleIdentifier ?? "<nil>", privacy: .public)")
                group.addTask { @MainActor in
                    do {
                        try await self.relaunchApp(app)
                    } catch {
                        self.logger.debug("applyOffset: relaunch FAILED for pid \(app.processIdentifier, privacy: .public) bundle=\(app.bundleIdentifier ?? "<nil>", privacy: .public) error=\(String(describing: error), privacy: .public)")
                        guard let name = app.localizedName else {
                            return
                        }
                        if app.bundleIdentifier == "com.apple.Spotlight" {
                            // Spotlight automatically relaunches, so only consider it a failure if it never quit.
                            if
                                let latestSpotlightInstance = NSRunningApplication.runningApplications(withBundleIdentifier: "com.apple.Spotlight").first,
                                latestSpotlightInstance.processIdentifier == app.processIdentifier
                            {
                                failedApps.append(name)
                            }
                        } else {
                            failedApps.append(name)
                        }
                    }
                }
            }
        }

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

private extension NSRunningApplication {
    /// A string to use for logging purposes.
    var logString: String {
        localizedName ?? bundleIdentifier ?? "<NIL>"
    }
}
