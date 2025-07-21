//
//  SourcePIDCache.swift
//  MenuBarItemService
//

import AXSwift
import Cocoa
import Combine
import os.lock

/// A cache for the source process identifiers for menu bar item windows.
///
/// We use the term "source process" to refer to the process that created
/// a menu bar item. We used to be able to use the window's `ownerPID` to
/// determine this information, but in macOS 26 Tahoe, all item windows
/// are owned by Control Center. We need to be able to accurately identify
/// each item, and the source process is a good way to do that. Knowing
/// the source process also gives us an accurate name to show in various
/// places throughout the interface.
///
/// We can find what we need using the Accessibility API, but it's quite
/// an intensive process. Since Accessibility blocks the main thread, the
/// cache lives in a separate XPC process, which the main process queries
/// asynchronously.
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
                guard let latestBounds = window.getLatestBounds() else {
                    // Failure here means the window probably doesn't
                    // exist anymore.
                    return nil
                }
                if latestBounds == cachedBounds {
                    return latestBounds
                }
                cachedBounds = latestBounds
                // Sleep interval increases with each attempt.
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

    /// Storage for the cache's observers.
    private var cancellables = Set<AnyCancellable>()

    /// Creates the shared cache.
    private init() { }

    /// Starts the observers for the cache.
    func start() {
        var c = Set<AnyCancellable>()

        NSWorkspace.shared.publisher(for: \.runningApplications)
            .sink { [weak self] runningApps in
                guard let self else {
                    return
                }

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
            .store(in: &c)

        cancellables = c
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

// MARK: - WindowInfo Extension

private extension WindowInfo {
    /// Returns the latest bounds of the window.
    func getLatestBounds() -> CGRect? {
        Bridging.getWindowBounds(for: windowID)
    }
}
