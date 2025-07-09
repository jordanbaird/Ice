//
//  MenuBarItemSourceCache.swift
//  Ice
//

import AXSwift
import Cocoa
import Combine
import OSLog

// MARK: - MenuBarItemSourceCache

@available(macOS 26.0, *)
enum MenuBarItemSourceCache {
    private static let concurrentQueue = DispatchQueue.queue(
        label: "MenuBarItemSourceCache.concurrentQueue",
        qos: .userInteractive,
        attributes: .concurrent
    )

    @MainActor
    static func start(with permissions: AppPermissions) {
        Storage.start(with: permissions)
    }

    @discardableResult
    private static func updateCachedPID(for window: WindowInfo) -> pid_t? {
        let windowID = window.windowID

        for runningApp in Storage.getRunningApps() {
            // Since we're running concurrently, we could have a pid
            // at any point.
            if let pid = Storage.getPID(for: windowID) {
                return pid
            }

            // IMPORTANT: These checks help prevent some major thread
            // blocking caused by the AX APIs.
            guard
                runningApp.isFinishedLaunching,
                !runningApp.isTerminated,
                runningApp.activationPolicy != .prohibited
            else {
                continue
            }

            guard
                let app = Application(runningApp),
                let bar: UIElement = try? app.attribute(.extrasMenuBar)
            else {
                continue
            }

            for child in bar.children {
                if let pid = Storage.getPID(for: windowID) {
                    return pid
                }

                // Item window may have moved. Get the current bounds.
                guard let windowBounds = Bridging.getWindowBounds(for: windowID) else {
                    Storage.setPID(nil, for: windowID)
                    return nil
                }

                guard windowBounds == window.bounds else {
                    return nil
                }

                guard
                    let childFrame = child.frame,
                    childFrame.center.distance(to: windowBounds.center) <= 10
                else {
                    continue
                }

                let pid = runningApp.processIdentifier
                Storage.setPID(pid, for: windowID)
                return pid
            }
        }

        return nil
    }

    static func getCachedPID(for window: WindowInfo) -> pid_t? {
        if let pid = Storage.getPID(for: window.windowID) {
            return pid
        }
        return concurrentQueue.sync {
            updateCachedPID(for: window)
        }
    }
}

// MARK: - MenuBarItemSourceCache.Storage

@available(macOS 26.0, *)
extension MenuBarItemSourceCache {
    private enum Storage {
        private static let publisherQueue = DispatchQueue.queue(
            label: "MenuBarItemSourceCache.Storage.publisherQueue",
            qos: .userInteractive
        )
        private static let pidsQueue = DispatchQueue.queue(
            label: "MenuBarItemSourceCache.Storage.pidsQueue",
            qos: .userInteractive
        )
        private static let runningAppsQueue = DispatchQueue.queue(
            label: "MenuBarItemSourceCache.Storage.runningAppsQueue",
            qos: .userInteractive
        )

        private static var pids = [CGWindowID: pid_t]()
        private static var runningApps = [NSRunningApplication]()
        private static var cancellable: AnyCancellable?

        static func getPID(for windowID: CGWindowID) -> pid_t? {
            pidsQueue.sync { pids[windowID] }
        }

        static func setPID(_ pid: pid_t?, for windowID: CGWindowID) {
            pidsQueue.sync { pids[windowID] = pid }
        }

        static func getRunningApps() -> [NSRunningApplication] {
            runningAppsQueue.sync { runningApps }
        }

        @MainActor
        static func start(with permissions: AppPermissions) {
            cancellable = NSWorkspace.shared.publisher(for: \.runningApplications)
                .receive(on: publisherQueue)
                .sink { [weak permissions] runningApps in
                    guard
                        let permissions,
                        permissions.accessibility.hasPermission
                    else {
                        return
                    }

                    pidsQueue.sync {
                        let newPIDs = Set(runningApps.map { $0.processIdentifier })
                        for (key, value) in pids where !newPIDs.contains(value) {
                            pids.removeValue(forKey: key)
                        }
                    }

                    runningAppsQueue.sync {
                        self.runningApps = runningApps
                    }

                    for window in MenuBarItem.getMenuBarItemWindows(option: .activeSpace) {
                        concurrentQueue.async {
                            updateCachedPID(for: window)
                        }
                    }
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
