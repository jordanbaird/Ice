//
//  WindowCaptureManager.swift
//  Ice
//

import OSLog
import ScreenCaptureKit

/// A type that manages the capturing of window images.
class WindowCaptureManager {

    // MARK: Capture Image

    /// Captures a portion of a window as an image.
    ///
    /// - Parameters:
    ///   - window: The window to capture.
    ///   - bounds: A rectangle within the coordinate space of `window` to capture.
    ///     Pass `nil` to capture the entire window.
    ///
    /// - Returns: An image that contains the area of `window` inside of `bounds`.
    static func captureImage(window: SCWindow, bounds: CGRect? = nil) -> CGImage? {
        if !window.isOnScreen && !window.isActive {
            return nil
        }
        if #available(macOS 14.0, *) {
            return captureImageScreenCaptureKit(window: window, bounds: bounds)
        } else {
            return captureImageCoreGraphics(window: window, bounds: bounds)
        }
    }

    // MARK: ScreenCaptureKit

    @available(macOS 14.0, *)
    private static func captureImageScreenCaptureKit(window: SCWindow, bounds: CGRect?) -> CGImage? {
        let contentFilter = SCContentFilter(desktopIndependentWindow: window)

        let windowBounds = CGRect(origin: .zero, size: window.frame.size)
        let sourceRect = if let bounds {
            if bounds.isEmpty {
                windowBounds
            } else {
                bounds
            }
        } else {
            windowBounds
        }

        guard windowBounds.contains(sourceRect) else {
            // return early, as SCScreenshotManager never finishes
            // if sourceRect isn't inside windowBounds
            return nil
        }

        // scale sourceRect by the scale factor of the screen
        let scale = getDisplayScaleFactor(CGMainDisplayID())
        let scaledSourceRect = sourceRect.applying(CGAffineTransform(scaleX: scale, y: scale))

        let configuration = SCStreamConfiguration()
        configuration.sourceRect = scaledSourceRect
        configuration.width = Int(scaledSourceRect.width)
        configuration.height = Int(scaledSourceRect.height)
        configuration.showsCursor = false

        var capturedImage: CGImage?

        let semaphore = DispatchSemaphore(value: 0)
        SCScreenshotManager.captureImage(
            contentFilter: contentFilter,
            configuration: configuration
        ) { image, error in
            capturedImage = image
            if let error {
                Logger.windowCapture.error(
                    """
                    WindowCaptureManager\
                    \(window.title.map { $0.isEmpty ? $0 : " (" + $0 + ")" } ?? ""): \
                    \(error.localizedDescription)
                    """
                )
            }
            semaphore.signal()
        }
        semaphore.wait()

        return capturedImage
    }

    // MARK: CoreGraphics

    @available(macOS, deprecated: 14.0)
    private static func captureImageCoreGraphics(window: SCWindow, bounds: CGRect?) -> CGImage? {
        // CGWindowListCreateImage captures the window bounds
        // if bounds is a null rectangle
        var sourceRect = bounds ?? .null
        if !sourceRect.isNull {
            let windowBounds = CGRect(origin: .zero, size: window.frame.size)
            guard windowBounds.contains(sourceRect) else {
                // return early to match the behavior of captureImageScreenCaptureKit
                return nil
            }
            // offset sourceRect into the coordinate space of the window
            sourceRect.origin.x += window.frame.origin.x
            sourceRect.origin.y += window.frame.origin.y
        }
        let listOption = CGWindowListOption.optionIncludingWindow
        let imageOption = CGWindowImageOption.boundsIgnoreFraming
        return CGWindowListCreateImage(sourceRect, listOption, window.windowID, imageOption)
    }

    // MARK: Helpers

    /// Returns the scale factor of the display with the given identifier.
    private static func getDisplayScaleFactor(_ displayID: CGDirectDisplayID) -> CGFloat {
        guard let mode = CGDisplayCopyDisplayMode(displayID) else {
            return 1
        }
        return CGFloat(mode.pixelWidth) / CGFloat(mode.width)
    }
}

// MARK: - Logger
extension Logger {
    static let windowCapture = Logger.mainSubsystem(category: "WindowCapture")
}
