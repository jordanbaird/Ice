//
//  SourcePIDCache.swift
//  MenuBarItemService
//

import AXSwift
import Cocoa
import Combine
import os

/// A cache for the source process identifiers for menu bar item windows.
///
/// We use the term "source process" to refer to the process that created
/// a menu bar item. Originally, we used the CGWindowList API to get the
/// window's owning process (`kCGWindowOwnerPID`), which was always the
/// source process. However, as of macOS 26, item windows are owned by
/// the Control Center.
///
/// We can find what we need using the Accessibility API, but doing it
/// efficiently ends up being a fairly complex process. Since calls to
/// Accessibility are thread blocking, we do most of the heavy lifting
/// in a dedicated XPC service, which we then call asynchronously from
/// the main app.
final class SourcePIDCache {
    /// The timeout, in seconds, for the accessibility messages that the
    /// cache sends to other apps.
    ///
    /// A cached extras menu bar skips the check for an unresponsive app,
    /// so a stuck app would otherwise block a request for the default
    /// timeout of 6 seconds.
    private static let messagingTimeout: Float = 1

    /// The interval, in seconds, before the cache looks again for the
    /// extras menu bar of an app that didn't have one.
    ///
    /// Most apps don't have an extras menu bar, and looking for one
    /// calls into the app, so the cache doesn't look on every request.
    private static let extrasMenuBarRetryInterval: TimeInterval = 10

    /// The interval, in seconds, before the cache looks again for the
    /// source process of a window that it couldn't find.
    private static let windowRetryInterval: TimeInterval = 2

    /// An object that contains a running application and provides an
    /// interface to access relevant information, such as its process
    /// identifier and extras menu bar.
    ///
    /// Lookups for different windows can run at the same time, so the
    /// object guards its mutable state with a lock, which it never holds
    /// while calling into another app.
    private final class CachedApplication {
        /// The app's extras menu bar, or the date after which to look
        /// for it again.
        private struct ExtrasMenuBarState {
            var bar: UIElement?
            var retryDate: Date?
        }

        private let runningApp: NSRunningApplication
        private let extrasMenuBar = OSAllocatedUnfairLock(uncheckedState: ExtrasMenuBarState())

        /// The app's process identifier.
        var processIdentifier: pid_t {
            runningApp.processIdentifier
        }

        /// A Boolean value indicating whether the app's extras menu
        /// bar has been successfully created and stored.
        var hasExtrasMenuBar: Bool {
            extrasMenuBar.withLockUnchecked { $0.bar != nil }
        }

        /// A Boolean value indicating whether the app is in a valid
        /// state for making accessibility calls.
        var isValidForAccessibility: Bool {
            // These checks help prevent blocking that can occur when
            // calling AX APIs while the app is an invalid state.
            runningApp.isFinishedLaunching &&
            !runningApp.isTerminated &&
            runningApp.activationPolicy != .prohibited &&
            !Bridging.isProcessUnresponsive(processIdentifier)
        }

        /// Creates a `CachedApplication` instance with the given running
        /// application.
        init(_ runningApp: NSRunningApplication) {
            self.runningApp = runningApp
        }

        /// Returns the accessibility element representing the app's extras
        /// menu bar, creating it if necessary.
        ///
        /// When the element is first created, it gets stored for efficient
        /// access on subsequent calls. When creating it fails, the app isn't
        /// asked again until ``extrasMenuBarRetryInterval`` has passed.
        ///
        /// - Parameter ignoringRetryDelay: If `true`, looks for the extras
        ///   menu bar even if a recent attempt failed.
        func getOrCreateExtrasMenuBar(ignoringRetryDelay: Bool) -> UIElement? {
            let state = extrasMenuBar.withLockUnchecked { $0 }
            if let bar = state.bar {
                return bar
            }
            if !ignoringRetryDelay, let retryDate = state.retryDate, retryDate > .now {
                return nil
            }
            guard let bar = createExtrasMenuBar() else {
                extrasMenuBar.withLockUnchecked { state in
                    state.retryDate = .now.addingTimeInterval(extrasMenuBarRetryInterval)
                }
                return nil
            }
            extrasMenuBar.withLockUnchecked { state in
                state.bar = bar
                state.retryDate = nil
            }
            return bar
        }

        /// Creates the accessibility element representing the app's
        /// extras menu bar.
        private func createExtrasMenuBar() -> UIElement? {
            guard
                isValidForAccessibility,
                let app = AXHelpers.application(for: runningApp)
            else {
                return nil
            }
            AXUIElementSetMessagingTimeout(app.element, messagingTimeout)
            guard let bar = AXHelpers.extrasMenuBar(for: app) else {
                return nil
            }
            AXUIElementSetMessagingTimeout(bar.element, messagingTimeout)
            return bar
        }
    }

    /// State for the cache.
    private struct State {
        var apps = [CachedApplication]()
        var pids = [CGWindowID: pid_t]()
        var retryDates = [CGWindowID: Date]()
    }

    /// Returns the latest bounds of the given window after ensuring
    /// that the bounds are stable (a.k.a. not currently changing).
    ///
    /// This method blocks until stable bounds can be determined, or
    /// until retrieving the bounds for the window fails.
    private static func stableBounds(for window: WindowInfo) -> CGRect? {
        var cachedBounds = window.bounds

        for n in 1...5 {
            guard let currentBounds = window.currentBounds() else {
                // Failure here means the window probably doesn't
                // exist anymore.
                return nil
            }
            if currentBounds == cachedBounds {
                return currentBounds
            }
            cachedBounds = currentBounds
            // Compute the sleep interval from the current attempt.
            Thread.sleep(forTimeInterval: TimeInterval(n) / 100)
        }

        return nil
    }

    /// Finds the process identifier for the window with the given bounds
    /// by searching the extras menu bars of the given apps.
    ///
    /// This method blocks while it calls into other apps, so it must not
    /// be called while holding the lock for the cache's state.
    ///
    /// - Parameters:
    ///   - windowBounds: The stable bounds of the window.
    ///   - apps: The apps to search.
    ///   - ignoringRetryDelay: If `true`, also searches apps that recently
    ///     failed to provide an extras menu bar.
    private static func findPID(
        forWindowBounds windowBounds: CGRect,
        in apps: [CachedApplication],
        ignoringRetryDelay: Bool
    ) -> pid_t? {
        // Search the apps that are confirmed to have an extras menu
        // bar first.
        let apps = apps.filter { $0.hasExtrasMenuBar } + apps.filter { !$0.hasExtrasMenuBar }

        for app in apps {
            guard let bar = app.getOrCreateExtrasMenuBar(ignoringRetryDelay: ignoringRetryDelay) else {
                continue
            }
            for child in AXHelpers.children(for: bar) {
                AXUIElementSetMessagingTimeout(child.element, messagingTimeout)
                guard AXHelpers.isEnabled(child) else {
                    continue
                }
                guard
                    let childFrame = AXHelpers.frame(for: child),
                    childFrame.center.distance(to: windowBounds.center) <= 1
                else {
                    continue
                }
                return app.processIdentifier
            }
        }

        return nil
    }

    /// The shared cache.
    static let shared = SourcePIDCache()

    /// The cache's protected state.
    private let state = OSAllocatedUnfairLock(uncheckedState: State())

    /// Observer for running applications.
    private lazy var cancellable = NSWorkspace.shared.publisher(for: \.runningApplications).sink { [weak self] runningApps in
        guard let self else {
            return
        }

        Logger.default.debug("Received new running applications")

        let windowIDs = Bridging.getMenuBarWindowList(option: .itemsOnly)

        state.withLockUnchecked { state in
            // Convert the cached state to dictionaries keyed by pid to
            // allow for efficient repeated access.
            let appMappings = state.apps.reduce(into: [:]) { result, app in
                result[app.processIdentifier] = app
            }
            let pidMappings: [pid_t: [CGWindowID: pid_t]] = windowIDs.reduce(into: [:]) { result, windowID in
                if let pid = state.pids[windowID] {
                    result[pid, default: [:]][windowID] = pid
                }
            }

            // Create a new state that matches the current running apps.
            state = runningApps.reduce(into: State()) { result, app in
                let pid = app.processIdentifier

                if let app = appMappings[pid] {
                    // Prefer the cached app, as it may have already done
                    // the work to initialize its extras menu bar.
                    result.apps.append(app)
                } else {
                    // App wasn't in the cache, so it must be new.
                    result.apps.append(CachedApplication(app))
                }

                if let pids = pidMappings[pid] {
                    result.pids.merge(pids) { (_, new) in new }
                }
            }
        }
    }

    /// Creates the shared cache.
    private init() {
        Bridging.setProcessUnresponsiveTimeout(3)
    }

    /// Starts the observers for the cache.
    func start() {
        Logger.default.debug("Starting observers for source PID cache")
        _ = cancellable
    }

    /// Returns the cached process identifier for the given window,
    /// updating the cache if needed.
    func pid(for window: WindowInfo) -> pid_t? {
        // Snapshot the state and search outside the lock, so that a slow
        // app doesn't hold up other requests or the observer for running
        // applications.
        let (cachedPID, retryDate, apps) = state.withLockUnchecked { state in
            (state.pids[window.windowID], state.retryDates[window.windowID], state.apps)
        }
        if let cachedPID {
            return cachedPID
        }
        if let retryDate, retryDate > .now {
            return nil
        }
        guard
            AXHelpers.isProcessTrusted(),
            let windowBounds = Self.stableBounds(for: window)
        else {
            return nil
        }
        // The first search for a window also asks the apps that recently
        // had no extras menu bar, as the window may be their first item.
        let pid = Self.findPID(
            forWindowBounds: windowBounds,
            in: apps,
            ignoringRetryDelay: retryDate == nil
        )
        // Running apps may not change for a long time, so drop windows
        // that no longer exist while we're here.
        let windowIDs = Set(Bridging.getMenuBarWindowList())
        state.withLockUnchecked { state in
            // An empty list means that getting it failed.
            if !windowIDs.isEmpty {
                state.pids = state.pids.filter { windowIDs.contains($0.key) }
                state.retryDates = state.retryDates.filter { windowIDs.contains($0.key) }
            }
            if let pid {
                state.pids[window.windowID] = pid
                state.retryDates[window.windowID] = nil
            } else {
                state.retryDates[window.windowID] = .now.addingTimeInterval(Self.windowRetryInterval)
            }
        }
        return pid
    }
}
