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
        Signposts.measure("capture.windows") {
            performCaptureWindows(with: windowIDs, screenBounds: screenBounds, option: option)
        }
    }

    private static func performCaptureWindows(with windowIDs: [CGWindowID], screenBounds: CGRect?, option: CGWindowImageOption) -> CGImage? {
        if let array = Bridging.createCGWindowArray(with: windowIDs) {
            let bounds = screenBounds ?? .null
            // ScreenCaptureKit doesn't support capturing images of offscreen menu bar
            // items, so we unfortunately have to use the deprecated CGWindowList API.
            if let image = CGImage(windowListFromArrayScreenBounds: bounds, windowArray: array, imageOption: option) {
                return image
            }
        }
        // Never block the caller (this can run on the main thread): return the
        // last ScreenCaptureKit image, if any, and refresh it in the background.
        return SCKCapture.cachedImage(windowIDs: windowIDs, screenBounds: screenBounds, option: option)
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
///
/// Captures run in the background, at most a few at a time, with a timeout.
/// Callers never wait: they get the previous image (or `nil`) right away.
private enum SCKCapture {
    private struct Request: Hashable {
        let windowIDs: [CGWindowID]
        let screenBounds: CGRect?
        let optionRawValue: UInt32
    }

    /// The longest a background capture may take.
    private static let timeout: Duration = .seconds(2)

    private static let cache = BackgroundCaptureCache<Request, CGImageBox>(
        maxInFlight: 2,
        maxAge: 0.5,
        now: { ProcessInfo.processInfo.systemUptime },
        start: { request, operation in
            // The work ends (and frees its slot) only when SCK really returns:
            // cancellation is cooperative, so a timeout only expires the result.
            let work = Task.detached(priority: .userInitiated) {
                let image = await captureWindowsAsync(request)
                operation.deliver(image.map(CGImageBox.init))
                operation.finish()
            }
            Task.detached(priority: .utility) {
                try? await Task.sleep(for: timeout)
                work.cancel()
                operation.deliver(nil)   // ignored if the work already delivered
            }
        }
    )

    private final class CGImageBox: @unchecked Sendable {
        let image: CGImage
        init(_ image: CGImage) { self.image = image }
    }

    static func cachedImage(windowIDs: [CGWindowID], screenBounds: CGRect?, option: CGWindowImageOption) -> CGImage? {
        cache.value(for: Request(windowIDs: windowIDs, screenBounds: screenBounds, optionRawValue: option.rawValue))?.image
    }

    // Cached shareable content, refreshed when it is stale or when a
    // requested window is missing from it.
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

    private static func captureWindowsAsync(_ request: Request) async -> CGImage? {
        let option = CGWindowImageOption(rawValue: request.optionRawValue)
        guard !Task.isCancelled, let content = await shareableContent(needing: Set(request.windowIDs)) else {
            return nil
        }
        // Don't start the next ScreenCaptureKit step for an expired operation.
        guard !Task.isCancelled else {
            return nil
        }
        let windowsByID = Dictionary(content.windows.map { ($0.windowID, $0) }) { first, _ in first }
        // Keep the caller's front-to-back order and drop offscreen windows,
        // which ScreenCaptureKit cannot capture.
        let windows = request.windowIDs.compactMap { windowsByID[$0] }.filter(\.isOnScreen)
        guard !windows.isEmpty else {
            return nil
        }
        let unionFrame = windows.reduce(CGRect.null) { $0.union($1.frame) }
        var globalRect = request.screenBounds ?? unionFrame
        if globalRect.isNull || globalRect.isEmpty {
            globalRect = unionFrame
        }
        guard
            let display = content.displays.first(where: { $0.frame.intersects(globalRect) }),
            let screen = NSScreen.screens.first(where: { $0.displayID == display.displayID })
        else {
            return nil
        }
        let nominal = option.contains(.nominalResolution)
        // `sourceRect` is in the display's own coordinate space, not in global
        // coordinates (see `SCKGeometry`).
        guard let geometry = SCKGeometry.sourceRect(
            forGlobalRect: globalRect,
            onDisplay: display.frame,
            scale: nominal ? 1 : screen.backingScaleFactor
        ) else {
            return nil
        }
        guard !Task.isCancelled else {
            return nil
        }
        let filter = SCContentFilter(display: display, including: windows)
        let configuration = SCStreamConfiguration()
        configuration.sourceRect = geometry.rect
        configuration.width = Int(geometry.pixelSize.width)
        configuration.height = Int(geometry.pixelSize.height)
        configuration.showsCursor = false
        configuration.captureResolution = nominal ? .nominal : .best
        configuration.ignoreShadowsDisplay = option.contains(.boundsIgnoreFraming)
        configuration.ignoreGlobalClipDisplay = true
        return try? await SCScreenshotManager.captureImage(contentFilter: filter, configuration: configuration)
    }
}
