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
    /// An object that contains a running application and provides an
    /// interface to access relevant information, such as its process
    /// identifier and extras menu bar.
    private final class CachedApplication {
        private let runningApp: NSRunningApplication
        private var extrasMenuBar: UIElement?

        /// The app's process identifier.
        var processIdentifier: pid_t {
            runningApp.processIdentifier
        }

        /// A Boolean value indicating whether the app's extras menu
        /// bar has been successfully created and stored.
        var hasExtrasMenuBar: Bool {
            extrasMenuBar != nil
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
        /// access on subsequent calls.
        func getOrCreateExtrasMenuBar() -> UIElement? {
            if let extrasMenuBar {
                return extrasMenuBar
            }
            guard
                isValidForAccessibility,
                let app = AXHelpers.application(for: runningApp),
                let bar = AXHelpers.extrasMenuBar(for: app)
            else {
                return nil
            }
            extrasMenuBar = bar
            return bar
        }
    }

    /// State for the cache.
    private struct State {
        /// The duration that a failed lookup is remembered before the
        /// window is scanned again.
        static let failedLookupTTL: TimeInterval = 5

        /// The maximum rate at which unknown windows are scanned. Every
        /// scan of an unknown window performs accessibility queries
        /// against all running applications, so this bounds the amount
        /// of work a client can trigger.
        static let maxUnknownScansPerSecond = 10

        var apps = [CachedApplication]()
        var pids = [CGWindowID: pid_t]()

        /// The times at which lookups last failed, keyed by window ID.
        var failedLookups = [CGWindowID: Date]()

        /// A fractional token bucket limiting scans of unknown windows.
        var scanTokens = Double(maxUnknownScansPerSecond)
        var lastScanTokenRefill = Date()

        /// Refills the scan token bucket based on the time elapsed
        /// since the last refill.
        mutating func refillScanTokens(now: Date) {
            let elapsed = now.timeIntervalSince(lastScanTokenRefill)
            guard elapsed > 0 else {
                return
            }
            scanTokens = min(Double(Self.maxUnknownScansPerSecond), scanTokens + elapsed * Double(Self.maxUnknownScansPerSecond))
            lastScanTokenRefill = now
        }

        /// Prunes the failed lookup map if it has grown too large, as
        /// can happen when a client floods the service with requests
        /// for random window IDs.
        mutating func pruneFailedLookups(now: Date) {
            guard failedLookups.count > 512 else {
                return
            }
            let recent = failedLookups
                .filter { now.timeIntervalSince($0.value) < Self.failedLookupTTL }
            failedLookups = recent
        }

        /// Returns the latest bounds of the given window after ensuring
        /// that the bounds are stable (a.k.a. not currently changing).
        ///
        /// This method blocks until stable bounds can be determined, or
        /// until retrieving the bounds for the window fails.
        private mutating func stableBounds(for windowID: CGWindowID, initialBounds: CGRect) -> CGRect? {
            var cachedBounds = initialBounds

            for n in 1...5 {
                guard let currentBounds = Bridging.getWindowBounds(for: windowID) else {
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

        /// Reorders the cached apps so that those that are confirmed
        /// to have an extras menu bar are first in the array.
        private mutating func partitionApps() {
            var lhs = [CachedApplication]()
            var rhs = [CachedApplication]()

            for app in apps {
                if app.hasExtrasMenuBar {
                    lhs.append(app)
                } else {
                    rhs.append(app)
                }
            }

            apps = lhs + rhs
        }

        /// Updates the cached process identifier for the given window.
        mutating func updatePID(for windowID: CGWindowID, initialBounds: CGRect) {
            guard
                AXHelpers.isProcessTrusted(),
                let windowBounds = stableBounds(for: windowID, initialBounds: initialBounds)
            else {
                return
            }

            partitionApps()

            for app in apps {
                guard let bar = app.getOrCreateExtrasMenuBar() else {
                    continue
                }
                for child in AXHelpers.children(for: bar) {
                    guard AXHelpers.isEnabled(child) else {
                        continue
                    }
                    guard
                        let childFrame = AXHelpers.frame(for: child),
                        childFrame.center.distance(to: windowBounds.center) <= 1
                    else {
                        continue
                    }
                    pids[windowID] = app.processIdentifier
                    return
                }
            }
        }
    }

    /// The shared cache.
    static let shared = SourcePIDCache()

    /// The cache's protected state.
    private let state = OSAllocatedUnfairLock(initialState: State())

    /// Observer for running applications.
    private lazy var cancellable = NSWorkspace.shared.publisher(for: \.runningApplications).sink { [weak self] runningApps in
        guard let self else {
            return
        }

        Logger.default.debug("Received new running applications")

        let windowIDs = Bridging.getMenuBarWindowList(option: .itemsOnly)

        state.withLock { state in
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
    func pid(for query: MenuBarItemService.SourcePIDQuery) -> pid_t? {
        state.withLock { state in
            if let pid = state.pids[query.windowID] {
                return pid
            }

            let now = Date()
            state.refillScanTokens(now: now)

            // Don't rescan a window whose last lookup recently failed.
            if
                let failedAt = state.failedLookups[query.windowID],
                now.timeIntervalSince(failedAt) < State.failedLookupTTL
            {
                return nil
            }

            // Don't perform expensive scans of unknown windows at an
            // unbounded rate.
            guard state.scanTokens >= 1 else {
                Logger.default.warning("Rate limiting source PID lookups for unknown windows")
                return nil
            }
            state.scanTokens -= 1

            state.updatePID(for: query.windowID, initialBounds: query.bounds)

            if state.pids[query.windowID] == nil {
                state.failedLookups[query.windowID] = now
                state.pruneFailedLookups(now: now)
            } else {
                state.failedLookups.removeValue(forKey: query.windowID)
            }
            return state.pids[query.windowID]
        }
    }
}
