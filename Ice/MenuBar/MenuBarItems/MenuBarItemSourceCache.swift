//
//  MenuBarItemSourceCache.swift
//  Ice
//

import AXSwift
import Cocoa
import Combine
import os.lock

// MARK: - MenuBarItemSourceCache

@available(macOS 26.0, *)
enum MenuBarItemSourceCache {
    private static let axQueue = DispatchQueue.queue(
        label: "MenuBarItemSourceCache.axQueue",
        qos: .utility,
        attributes: .concurrent
    )
    private static let serialWorkQueue = DispatchQueue(
        label: "MenuBarItemSourceCache.serialWorkQueue",
        qos: .userInteractive
    )
    private static let concurrentWorkQueue = DispatchQueue(
        label: "MenuBarItemSourceCache.concurrentWorkQueue",
        qos: .userInteractive,
        attributes: .concurrent
    )

    private final class CachedApplication: Sendable {
        private struct ExtrasMenuBarLazyStorage: @unchecked Sendable {
            var extrasMenuBar: UIElement?
            var hasInitialized = false
        }

        private let runningApp: NSRunningApplication
        private let extrasMenuBarState = OSAllocatedUnfairLock(initialState: ExtrasMenuBarLazyStorage())

        var processIdentifier: pid_t {
            runningApp.processIdentifier
        }

        var extrasMenuBar: UIElement? {
            extrasMenuBarState.withLock { storage in
                if storage.hasInitialized {
                    return storage.extrasMenuBar
                }

                defer {
                    storage.hasInitialized = true
                }

                // These checks help limit blocks that can occur when
                // calling the AX APIs (app could be unresponsive, or
                // in some other invalid state).
                guard
                    !Bridging.isProcessUnresponsive(processIdentifier),
                    runningApp.isFinishedLaunching,
                    !runningApp.isTerminated,
                    runningApp.activationPolicy != .prohibited
                else {
                    return nil
                }

                storage.extrasMenuBar = axQueue.sync {
                    guard let app = Application(runningApp) else {
                        return nil
                    }
                    return try? app.attribute(.extrasMenuBar)
                }

                return storage.extrasMenuBar
            }
        }

        init(_ runningApp: NSRunningApplication) {
            self.runningApp = runningApp
        }
    }

    private struct State: Sendable {
        var apps = [CachedApplication]()
        var pids = [CGWindowID: pid_t]()

        mutating func updateCachedPID(for window: WindowInfo) {
            let windowID = window.windowID

            for app in apps {
                // Since we're running concurrently, we could have a pid
                // at any point.
                if pids[windowID] != nil {
                    return
                }

                guard let bar = app.extrasMenuBar else {
                    continue
                }

                for child in axQueue.sync(execute: { bar.children }) {
                    if pids[windowID] != nil {
                        return
                    }

                    // Item window may have moved. Get the current bounds.
                    guard let windowBounds = Bridging.getWindowBounds(for: windowID) else {
                        pids.removeValue(forKey: windowID)
                        return
                    }

                    guard windowBounds == window.bounds else {
                        return
                    }

                    guard
                        let childFrame = axQueue.sync(execute: { child.frame }),
                        childFrame.center.distance(to: windowBounds.center) <= 10
                    else {
                        continue
                    }

                    pids[windowID] = app.processIdentifier
                    return
                }
            }
        }
    }

    private static let state = OSAllocatedUnfairLock(initialState: State())
    private static var cancellable: AnyCancellable?

    @MainActor
    static func start(with permissions: AppPermissions) {
        cancellable = NSWorkspace.shared.publisher(for: \.runningApplications)
            .receive(on: serialWorkQueue)
            .sink { [weak permissions] runningApps in
                guard
                    let permissions,
                    permissions.accessibility.hasPermission
                else {
                    return
                }

                state.withLock { state in
                    // Convert the cached state to dictionaries keyed by pid to
                    // allow for efficient repeated access.
                    let appMappings = state.apps.reduce(into: [:]) { result, app in
                        result[app.processIdentifier] = app
                    }
                    let pidMappings = state.pids.reduce(into: [:]) { result, pair in
                        result[pair.value, default: []].append(pair)
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

                for window in MenuBarItem.getMenuBarItemWindows(option: []) {
                    concurrentWorkQueue.async {
                        state.withLock { state in
                            state.updateCachedPID(for: window)
                        }
                    }
                }
            }
    }

    static func getCachedPID(for window: WindowInfo) -> pid_t? {
        concurrentWorkQueue.sync {
            state.withLock { state in
                if let pid = state.pids[window.windowID] {
                    return pid
                }
                state.updateCachedPID(for: window)
                return state.pids[window.windowID]
            }
        }
    }
}

// MARK: - DispatchQueue Helper

private extension DispatchQueue {
    /// Creates and returns a new dispatch queue that targets the global
    /// system queue with the specified quality-of-service class.
    static func queue(
        label: String,
        qos: DispatchQoS.QoSClass,
        attributes: Attributes = []
    ) -> DispatchQueue {
        let target: DispatchQueue = .global(qos: qos)
        return DispatchQueue(label: label, attributes: attributes, target: target)
    }
}
