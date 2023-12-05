//
//  ScreenshotManager.swift
//  Ice
//

import ScreenCaptureKit

/// A type that captures screenshots.
class ScreenshotManager {
    /// Options that affect the image or images returned from a capture.
    struct CaptureOptions: OptionSet {
        let rawValue: Int

        /// If the `screenBounds` parameter of the capture is `nil`,
        /// captures only the window area and ignores the area occupied
        /// by any framing effects.
        static let ignoreFraming = CaptureOptions(rawValue: 1 << 0)

        /// Captures only the shadow effects of the provided windows.
        static let onlyShadows = CaptureOptions(rawValue: 1 << 1)

        /// Fills the partially or fully transparent areas of the capture
        /// with a solid white backing color, resulting in an image that
        /// is fully opaque.
        static let shouldBeOpaque = CaptureOptions(rawValue: 1 << 2)

        /// The cursor is shown in the capture.
        static let showsCursor = CaptureOptions(rawValue: 1 << 3)
    }

    /// An error that can occur during a capture.
    enum CaptureError: Error {
        /// The provided window is not on screen.
        case windowOffScreen

        /// The source rectangle of the capture is outside the bounds
        /// of the provided window.
        case sourceRectOutOfBounds
    }

    /// Captures the given window as an image.
    ///
    /// - Parameters:
    ///   - window: The window to capture.
    ///   - display: The display that determines the scale factor of the
    ///     capture. Usually this is the display that contains the window.
    ///     Pass `nil` to use the main display.
    ///   - captureRect: The rectangle to capture, relative to the coordinate
    ///     space of the window. Pass `nil` to capture the entire window.
    ///   - resolution: The resolution of the capture.
    ///   - options: Additional parameters for the capture.
    static func captureImage(
        window: SCWindow,
        display: SCDisplay? = nil,
        captureRect: CGRect? = nil,
        resolution: SCCaptureResolutionType = .automatic,
        options: CaptureOptions = []
    ) async throws -> CGImage {
        guard window.isOnScreen else {
            throw CaptureError.windowOffScreen
        }

        let captureRect = captureRect ?? .null
        let windowBounds = CGRect(origin: .zero, size: window.frame.size)
        let sourceRect = if captureRect.isNull {
            windowBounds
        } else {
            captureRect
        }

        guard windowBounds.contains(sourceRect) else {
            throw CaptureError.sourceRectOutOfBounds
        }

        let contentFilter = SCContentFilter(desktopIndependentWindow: window)
        let configuration = SCStreamConfiguration()

        let displayID = display?.displayID ?? CGMainDisplayID()
        let scale = getDisplayScaleFactor(displayID)

        configuration.sourceRect = sourceRect
        configuration.width = Int(sourceRect.width * scale)
        configuration.height = Int(sourceRect.height * scale)
        configuration.captureResolution = resolution
        configuration.ignoreShadowsSingleWindow = options.contains(.ignoreFraming)
        configuration.capturesShadowsOnly = options.contains(.onlyShadows)
        configuration.shouldBeOpaque = options.contains(.shouldBeOpaque)
        configuration.showsCursor = options.contains(.showsCursor)

        return try await SCScreenshotManager.captureImage(
            contentFilter: contentFilter,
            configuration: configuration
        )
    }

    private static func getDisplayScaleFactor(_ displayID: CGDirectDisplayID) -> CGFloat {
        guard let mode = CGDisplayCopyDisplayMode(displayID) else {
            return 1
        }
        return CGFloat(mode.pixelWidth) / CGFloat(mode.width)
    }
}
