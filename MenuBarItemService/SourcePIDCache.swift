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
/// a given menu bar item. Originally, we could use the CGWindowList API,
/// as the item window's `kCGWindowOwnerPID` was always equivalent to the
/// source process identifier. However, as of macOS 26, all item windows
/// are owned by the Control Center.
///
/// We can still what we need using the Accessibility API, but doing it
/// efficiently ends up being fairly complex. It doesn't help that calls
/// to Accessibility are thread blocking. We resolve this by doing most
/// of the heavy lifting in a dedicated XPC service, which we then call
/// asynchronously from the main app.
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
        var apps = [CachedApplication]()
        var pids = [CGWindowID: pid_t]()

        /// Returns the latest bounds of the given window after ensuring
        /// that the bounds are stable (a.k.a. not currently changing).
        ///
        /// This method blocks until stable bounds can be determined, or
        /// until retrieving the bounds for the window fails.
        private func stableBounds(for window: WindowInfo) -> CGRect? {
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
        mutating func updatePID(for window: WindowInfo) {
            guard
                AXHelpers.isProcessTrusted(),
                let windowBounds = stableBounds(for: window)
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
                    pids[window.windowID] = app.processIdentifier
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

        Logger.general.debug("Received new running applications")

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
        Logger.general.debug("Starting observers for source PID cache")
        _ = cancellable
    }

    /// Returns the cached process identifier for the given window,
    /// updating the cache if needed.
    func pid(for window: WindowInfo) -> pid_t? {
        state.withLock { state in
            if let pid = state.pids[window.windowID] {
                return pid
            }
            state.updatePID(for: window)
            return state.pids[window.windowID]
        }
    }
}
