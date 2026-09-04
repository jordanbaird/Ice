//
//  ScreenCapture.swift
//  Ice
//

import CoreGraphics
import Foundation
import ScreenCaptureKit

/// A namespace for screen capture operations.
enum ScreenCapture {

    // MARK: Permissions

    /// Returns a Boolean value that indicates whether the app has screen
    /// capture permissions.
    ///
    /// Menu bar item windows no longer expose their titles on macOS 26, where
    /// the system reparents status items under Control Center. The title-based
    /// heuristic below therefore reports `false` on macOS 26 no matter what the
    /// user has granted, so we ask ScreenCaptureKit directly instead.
    static func checkPermissions() -> Bool {
        if #available(macOS 26.0, *) {
            return SCKPermissions.check()
        }
        for windowID in Bridging.getMenuBarWindowList(option: [.itemsOnly, .activeSpace]) {
            guard
                let window = WindowInfo(windowID: windowID),
                window.owningApplication != .current // Skip windows we own.
            else {
                continue
            }
            return window.title != nil
        }
        // CGPreflightScreenCaptureAccess() only returns an initial value,
        // but we can use it as a fallback.
        return CGPreflightScreenCaptureAccess()
    }

    /// Returns a Boolean value that indicates whether the app has screen
    /// capture permissions.
    ///
    /// This function caches its initial result and returns it on subsequent
    /// calls. Pass `true` to the `reset` parameter to replace the cached
    /// result with a newly computed value.
    static func cachedCheckPermissions(reset: Bool = false) -> Bool {
        enum Context {
            static var cachedResult: Bool?
        }
        if !reset, let result = Context.cachedResult {
            return result
        }
        let result = checkPermissions()
        Context.cachedResult = result
        return result
    }

    /// Requests screen capture permissions.
    static func requestPermissions() {
        if #available(macOS 15.0, *) {
            // CGRequestScreenCaptureAccess() is broken on macOS 15. We can
            // try accessing SCShareableContent to trigger a request if the
            // user doesn't have permissions.
            // TODO: Find out if we still need this as of macOS 26.
            SCShareableContent.getWithCompletionHandler { _, _ in }
        } else {
            CGRequestScreenCaptureAccess()
        }
    }

    // MARK: Capture Window(s)

    /// Captures a composite image of an array of windows.
    ///
    /// The windows are composited from front to back, according to the order
    /// of the `windowIDs` parameter.
    ///
    /// - Parameters:
    ///   - windowIDs: The identifiers of the windows to capture.
    ///   - screenBounds: The bounds to capture, specified in screen coordinates.
    ///     Pass `nil` to capture the minimum rectangle that encloses the windows.
    ///   - option: Options that specify which parts of the windows are captured.
    static func captureWindows(with windowIDs: [CGWindowID], screenBounds: CGRect? = nil, option: CGWindowImageOption = []) -> CGImage? {
        guard let array = Bridging.createCGWindowArray(with: windowIDs) else {
            return nil
        }
        let bounds = screenBounds ?? .null
        // ScreenCaptureKit doesn't support capturing images of offscreen menu bar
        // items, so we unfortunately have to use the deprecated CGWindowList API.
        return CGImage(windowListFromArrayScreenBounds: bounds, windowArray: array, imageOption: option)
    }

    /// Captures an image of a window.
    ///
    /// - Parameters:
    ///   - windowID: The identifier of the window to capture.
    ///   - screenBounds: The bounds to capture, specified in screen coordinates.
    ///     Pass `nil` to capture the minimum rectangle that encloses the window.
    ///   - option: Options that specify which parts of the window are captured.
    static func captureWindow(with windowID: CGWindowID, screenBounds: CGRect? = nil, option: CGWindowImageOption = []) -> CGImage? {
        captureWindows(with: [windowID], screenBounds: screenBounds, option: option)
    }
}

// MARK: - SCKPermissions

/// Screen recording permission checks for macOS 26 and later, where menu bar
/// item windows no longer expose titles and the title-based heuristic in
/// ``ScreenCapture/checkPermissions()`` can never succeed.
///
/// ``SCShareableContent`` is the authoritative source: it fails with a TCC
/// error when the app lacks the permission, and succeeds once it is granted.
/// It is only available asynchronously, so the result is cached and refreshed
/// in the background. Callers get the most recent known value immediately.
@available(macOS 26.0, *)
private enum SCKPermissions {
    private static let lock = NSLock()
    nonisolated(unsafe) private static var cachedResult = false
    nonisolated(unsafe) private static var lastRefresh: Date?
    nonisolated(unsafe) private static var isRefreshing = false

    /// The shortest interval between two background refreshes.
    private static let refreshInterval: TimeInterval = 1

    /// Returns the most recently cached permission state, scheduling a
    /// background refresh if the cached value is stale.
    static func check() -> Bool {
        lock.lock()
        let result = cachedResult
        let shouldRefresh = !isRefreshing && (lastRefresh.map { Date().timeIntervalSince($0) >= refreshInterval } ?? true)
        if shouldRefresh {
            isRefreshing = true
        }
        lock.unlock()

        if shouldRefresh {
            Task.detached(priority: .utility) {
                let granted = await hasPermission()
                lock.lock()
                cachedResult = granted
                lastRefresh = Date()
                isRefreshing = false
                lock.unlock()
            }
        }

        return result
    }

    /// Asks ScreenCaptureKit whether the app can enumerate shareable content.
    private static func hasPermission() async -> Bool {
        do {
            _ = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
            return true
        } catch {
            return false
        }
    }
}
