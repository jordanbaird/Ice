//
//  ScreenCapture.swift
//  Ice
//

import AppKit
import CoreGraphics
import ScreenCaptureKit

/// A namespace for screen capture operations.
enum ScreenCapture {

    // MARK: Permissions

    /// Returns a Boolean value that indicates whether the app has screen
    /// capture permissions.
    static func checkPermissions() -> Bool {
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
    /// The deprecated CGWindowList API is tried first, since it is the only API
    /// that can capture offscreen menu bar items. Starting with macOS 26.5 that
    /// API no longer returns images, so ScreenCaptureKit is used as a fallback.
    /// ScreenCaptureKit can only capture windows that are on screen; offscreen
    /// windows are simply left out of the result.
    ///
    /// - Parameters:
    ///   - windowIDs: The identifiers of the windows to capture.
    ///   - screenBounds: The bounds to capture, specified in screen coordinates.
    ///     Pass `nil` to capture the minimum rectangle that encloses the windows.
    ///   - option: Options that specify which parts of the windows are captured.
    static func captureWindows(with windowIDs: [CGWindowID], screenBounds: CGRect? = nil, option: CGWindowImageOption = []) -> CGImage? {
        if let array = Bridging.createCGWindowArray(with: windowIDs) {
            let bounds = screenBounds ?? .null
            // ScreenCaptureKit doesn't support capturing images of offscreen menu bar
            // items, so we unfortunately have to use the deprecated CGWindowList API.
            if let image = CGImage(windowListFromArrayScreenBounds: bounds, windowArray: array, imageOption: option) {
                return image
            }
        }
        return SCKCapture.captureWindows(with: windowIDs, screenBounds: screenBounds, option: option)
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

// MARK: - SCKCapture

/// ScreenCaptureKit-based window capture, used where the CGWindowList API
/// no longer produces images (macOS 26.5 and later).
private enum SCKCapture {
    /// The longest a synchronous caller waits for a capture.
    private static let timeout: DispatchTimeInterval = .seconds(2)

    /// Cached shareable content, refreshed when it is stale or when a
    /// requested window is missing from it.
    private static let contentLock = NSLock()
    nonisolated(unsafe) private static var cachedContent: (content: SCShareableContent, date: Date)?

    private static func shareableContent(needing windowIDs: Set<CGWindowID>) async -> SCShareableContent? {
        contentLock.lock()
        let cached = cachedContent
        contentLock.unlock()
        if
            let cached,
            Date().timeIntervalSince(cached.date) < 0.5,
            windowIDs.isSubset(of: cached.content.windows.map(\.windowID))
        {
            return cached.content
        }
        guard let content = try? await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true) else {
            return nil
        }
        contentLock.lock()
        cachedContent = (content, Date())
        contentLock.unlock()
        return content
    }

    /// A box for passing a capture result out of a detached task.
    private final class ResultBox<T>: @unchecked Sendable {
        var value: T?
    }

    /// Runs an async operation and waits for its result, bounded by `timeout`.
    private static func runBlocking<T: Sendable>(_ operation: @escaping @Sendable () async -> T?) -> T? {
        let semaphore = DispatchSemaphore(value: 0)
        let box = ResultBox<T>()
        Task.detached(priority: .userInitiated) {
            box.value = await operation()
            semaphore.signal()
        }
        guard semaphore.wait(timeout: .now() + timeout) == .success else {
            return nil
        }
        return box.value
    }

    static func captureWindows(with windowIDs: [CGWindowID], screenBounds: CGRect?, option: CGWindowImageOption) -> CGImage? {
        runBlocking {
            await captureWindowsAsync(with: windowIDs, screenBounds: screenBounds, option: option)
        }
    }

    private static func captureWindowsAsync(with windowIDs: [CGWindowID], screenBounds: CGRect?, option: CGWindowImageOption) async -> CGImage? {
        guard let content = await shareableContent(needing: Set(windowIDs)) else {
            return nil
        }
        let windowsByID = Dictionary(content.windows.map { ($0.windowID, $0) }) { first, _ in first }
        // Keep the caller's front-to-back order and drop offscreen windows,
        // which ScreenCaptureKit cannot capture.
        let windows = windowIDs.compactMap { windowsByID[$0] }.filter(\.isOnScreen)
        guard !windows.isEmpty else {
            return nil
        }
        let unionFrame = windows.reduce(CGRect.null) { $0.union($1.frame) }
        var rect = screenBounds ?? unionFrame
        if rect.isNull || rect.isEmpty {
            rect = unionFrame
        }
        guard
            let display = content.displays.first(where: { $0.frame.intersects(rect) }),
            let screen = NSScreen.screens.first(where: { $0.displayID == display.displayID })
        else {
            return nil
        }
        rect = rect.intersection(display.frame)
        guard !rect.isNull, rect.width >= 1, rect.height >= 1 else {
            return nil
        }
        let scale = option.contains(.nominalResolution) ? 1 : screen.backingScaleFactor
        let filter = SCContentFilter(display: display, including: windows)
        let configuration = SCStreamConfiguration()
        configuration.sourceRect = rect
        configuration.width = Int((rect.width * scale).rounded())
        configuration.height = Int((rect.height * scale).rounded())
        configuration.showsCursor = false
        configuration.captureResolution = option.contains(.nominalResolution) ? .nominal : .best
        configuration.ignoreShadowsDisplay = option.contains(.boundsIgnoreFraming)
        configuration.ignoreGlobalClipDisplay = true
        return try? await SCScreenshotManager.captureImage(contentFilter: filter, configuration: configuration)
    }
}
