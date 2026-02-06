//
//  ScreenCapture.swift
//  Ice
//

// MARK: - ScreenCapture

import CoreGraphics
import ScreenCaptureKit

/// A namespace for screen capture operations.
enum ScreenCapture {

    // MARK: Permissions

    /// Returns a Boolean value that indicates whether the app has screen capture permissions.
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
        // CGPreflightScreenCaptureAccess() only returns an initial value, but we can
        // use it as a fallback.
        return CGPreflightScreenCaptureAccess()
    }

    /// Returns a Boolean value that indicates whether the app has screen capture permissions.
    ///
    /// This function caches its initial result and returns it on subsequent calls. Pass `true`
    /// to the `reset` parameter to replace the cached result with a newly computed value.
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
            // TODO: Find out if we still need this.
            // CGRequestScreenCaptureAccess() is broken on macOS 15. SCShareableContent requires
            // screen capture permissions, and triggers a request if the user doesn't have them.
            SCShareableContent.getWithCompletionHandler { _, _ in }
        } else {
            CGRequestScreenCaptureAccess()
        }
    }

    // MARK: Capture Window(s)

    /// Queue for screen capture operations.
    private static let captureQueue = DispatchQueue(label: "ScreenCapture.captureQueue", qos: .userInteractive)

    /// Captures a composite image of an array of windows.
    ///
    /// The windows are composited from front to back, according to the order of the `windowIDs`
    /// parameter.
    ///
    /// - Parameters:
    ///   - windowIDs: The identifiers of the windows to capture.
    ///   - screenBounds: The bounds to capture, specified in screen coordinates. Pass `nil` to
    ///     capture the minimum rectangle that encloses the windows.
    ///   - option: Options that specify which parts of the windows are captured.
    static func captureWindows(with windowIDs: [CGWindowID], screenBounds: CGRect? = nil, option: CGWindowImageOption = []) -> CGImage? {
        guard let array = Bridging.createCGWindowArray(with: windowIDs) else {
            return nil
        }
        let bounds = screenBounds ?? .null
        return captureQueue.sync {
            CGImage.createWindowListImageFromArray(screenBounds: bounds, windowArray: array, imageOption: option)
        }
    }

    /// Captures an image of a window.
    ///
    /// - Parameters:
    ///   - windowID: The identifier of the window to capture.
    ///   - screenBounds: The bounds to capture, specified in screen coordinates. Pass `nil` to
    ///     capture the minimum rectangle that encloses the window.
    ///   - option: Options that specify which parts of the window are captured.
    static func captureWindow(with windowID: CGWindowID, screenBounds: CGRect? = nil, option: CGWindowImageOption = []) -> CGImage? {
        captureWindows(with: [windowID], screenBounds: screenBounds, option: option)
    }
}

// MARK: - WindowListImage Helper

/// A protocol to suppress warnings for the deprecated CGWindowList screen capture APIs.
///
/// ScreenCaptureKit doesn't support capturing composite images of offscreen menu bar items.
/// This should be replaced once it does.
private protocol WindowListImage {
    init?(windowListFromArrayScreenBounds: CGRect, windowArray: CFArray, imageOption: CGWindowImageOption)
}

private extension WindowListImage {
    @inline(__always) // Ensure a direct call to the initializer.
    static func createWindowListImageFromArray(screenBounds: CGRect, windowArray: CFArray, imageOption: CGWindowImageOption) -> Self? {
        Self(windowListFromArrayScreenBounds: screenBounds, windowArray: windowArray, imageOption: imageOption)
    }
}

extension CGImage: WindowListImage { }
