//
//  WindowCaptureManager.swift
//  Ice
//

import CoreGraphics
import ScreenCaptureKit

enum WindowCaptureManager {
    enum CaptureError: Error {
        case cgWindowListCreateImageError
    }

    enum CaptureResolution {
        case automatic
        case best
        case nominal
    }

    /// Captures the window as an image.
    ///
    /// - Parameters:
    ///   - bounds: The source rectangle to capture.
    ///   - resolution: The resolution of the capture.
    ///
    /// - Returns: An image that contains the area of the window inside of `bounds`.
    static func captureImage(
        window: SCWindow,
        bounds: CGRect,
        resolution: CaptureResolution
    ) async throws -> CGImage {
        if #available(macOS 14.0, *) {
            return try await captureImageScreenCaptureKit(
                window: window,
                bounds: bounds,
                resolution: resolution
            )
        } else {
            return try captureImageCoreGraphics(
                window: window,
                bounds: bounds,
                resolution: resolution
            )
        }
    }

    /// Captures the window as an image using the `ScreenCaptureKit` framework.
    ///
    /// - Parameters:
    ///   - bounds: The source rectangle to capture.
    ///   - resolution: The resolution of the capture.
    ///
    /// - Returns: An image that contains the area of the window inside of `bounds`.
    @available(macOS 14.0, *)
    static func captureImageScreenCaptureKit(
        window: SCWindow,
        bounds: CGRect,
        resolution: CaptureResolution
    ) async throws -> CGImage {
        let filter = SCContentFilter(desktopIndependentWindow: window)

        let config = SCStreamConfiguration()
        config.sourceRect = bounds
        config.width = Int(bounds.width)
        config.height = Int(bounds.height)
        config.showsCursor = false
        config.minimumFrameInterval = CMTime(value: 1, timescale: 1)
        config.captureResolution = switch resolution {
        case .automatic: .automatic
        case .best: .best
        case .nominal: .nominal
        }

        return try await SCScreenshotManager.captureImage(
            contentFilter: filter,
            configuration: config
        )
    }

    /// Captures the window as an image using the `CoreGraphics` framework.
    ///
    /// - Parameters:
    ///   - bounds: The source rectangle to capture.
    ///   - resolution: The resolution of the capture.
    ///
    /// - Returns: An image that contains the area of the window inside of `bounds`.
    @available(macOS, deprecated: 14.0)
    static func captureImageCoreGraphics(
        window: SCWindow,
        bounds: CGRect,
        resolution: CaptureResolution
    ) throws -> CGImage {
        let imageOption: CGWindowImageOption = switch resolution {
        case .automatic: []
        case .best: .bestResolution
        case .nominal: .nominalResolution
        }
        guard let image = CGWindowListCreateImage(bounds, [.optionIncludingWindow], window.windowID, imageOption) else {
            throw CaptureError.cgWindowListCreateImageError
        }
        return image
    }
}
