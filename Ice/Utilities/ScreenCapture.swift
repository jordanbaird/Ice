//
//  ScreenCapture.swift
//  Ice
//

import CoreGraphics
import CoreVideo
import Foundation
@preconcurrency import ScreenCaptureKit

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
            if window.title != nil {
                return true
            }
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
            static let lock = NSLock()
            static var cachedResult: Bool?
        }
        Context.lock.lock()
        defer { Context.lock.unlock() }
        // Cache both outcomes. Background Layout refreshes run frequently on
        // macOS 27; recomputing a negative result lets every refresh reach TCC
        // and can repeatedly surface the system consent alert. The dedicated
        // permission observer explicitly resets this cache while it polls, so
        // a newly granted permission still takes effect without a relaunch.
        if !reset, let cachedResult = Context.cachedResult {
            return cachedResult
        }
        let result = checkPermissions()
        Context.cachedResult = result
        return result
    }

    /// Requests screen capture permissions.
    static func requestPermissions() {
        if #available(macOS 27.0, *) {
            // On macOS 27, querying SCShareableContent while the current
            // binary is not authorized can repeatedly display the system
            // consent alert. Only use the explicit, user-initiated request.
            CGRequestScreenCaptureAccess()
        } else if #available(macOS 15.0, *) {
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

    // MARK: macOS 27 Menu Bar Capture

    @available(macOS 27.0, *)
    struct MenuBarCapture {
        let image: CGImage
        let windowFrame: CGRect
        let scale: CGFloat
    }

    /// Take one composited screen-region screenshot, then crop by live AX frames.
    /// Window/stream capture does not preserve all hosted status-item pixels on
    /// macOS 27. This screenshot API captures what is actually on the display.
    @available(macOS 27.0, *)
    static func captureMenuBarDisplayStrip(
        displayID: CGDirectDisplayID
    ) async -> MenuBarCapture? {
        guard cachedCheckPermissions() else { return nil }
        let displayFrame = CGDisplayBounds(displayID)
        guard displayFrame.width > 0, displayFrame.height > 0 else { return nil }
        let stripFrame = CGRect(
            x: displayFrame.minX,
            y: displayFrame.minY,
            width: displayFrame.width,
            height: min(40, displayFrame.height)
        )
        let scale = CGFloat(CGDisplayPixelsWide(displayID)) / displayFrame.width
        let configuration = SCScreenshotConfiguration()
        configuration.showsCursor = false
        configuration.dynamicRange = .sdr
        configuration.displayIntent = .local
        configuration.width = max(1, Int((stripFrame.width * scale).rounded()))
        configuration.height = max(1, Int((stripFrame.height * scale).rounded()))

        do {
            let output = try await SCScreenshotManager.captureScreenshot(
                rect: stripFrame, configuration: configuration
            )
            guard let image = output.sdrImage else { return nil }
            return MenuBarCapture(
                image: image,
                windowFrame: stripFrame,
                scale: CGFloat(image.width) / stripFrame.width
            )
        } catch {
            return nil
        }
    }
}
