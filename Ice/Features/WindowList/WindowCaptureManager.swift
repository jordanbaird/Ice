//
//  WindowCaptureManager.swift
//  Ice
//

import OSLog
import ScreenCaptureKit

/// A type that manages the capturing of window images.
class WindowCaptureManager {
    /// Options that affect the image or images returned from a window capture.
    struct CaptureOptions: OptionSet {
        let rawValue: Int

        /// If the `screenBounds` parameter of the capture is `nil`, captures only
        /// the window area and ignores the area occupied by any framing effects.
        static let ignoreFraming = CaptureOptions(rawValue: 1 << 0)
        /// Captures only the shadow effects of the provided windows.
        static let onlyShadows = CaptureOptions(rawValue: 1 << 1)
        /// Fills the partially or fully transparent areas of the capture with a
        /// solid white backing color, resulting in an image that is fully opaque.
        static let shouldBeOpaque = CaptureOptions(rawValue: 1 << 2)
    }

    /// Captures the given window as an image.
    ///
    /// - Parameters:
    ///   - window: The window to capture.
    ///   - captureRect: The rectangle to capture, relative to the coordinate
    ///     space of the window. Pass `nil` to capture the entire window.
    ///   - resolution: The resolution at which to capture the window.
    ///   - options: Options that affect the image returned from the capture.
    static func captureImage(
        window: SCWindow,
        captureRect: CGRect? = nil,
        resolution: SCCaptureResolutionType = .automatic,
        options: CaptureOptions = []
    ) -> CGImage? {
        guard window.isOnScreen else {
            // FIXME: Remove this check once Apple provides a way to capture off screen windows
            Logger.windowCapture.warning("Warning: window is not on screen and cannot be captured")
            return nil
        }

        let captureRect = captureRect ?? .null
        let windowBounds = CGRect(origin: .zero, size: window.frame.size)
        let sourceRect = captureRect.isNull ? windowBounds : captureRect
        guard windowBounds.contains(sourceRect) else {
            // capture will time out if we continue
            Logger.windowCapture.error("Error capturing image: sourceRect is not inside windowBounds")
            return nil
        }

        let contentFilter = SCContentFilter(desktopIndependentWindow: window)
        let configuration = SCStreamConfiguration()

        let scale = getDisplayScaleFactor(CGMainDisplayID())
        configuration.sourceRect = sourceRect
        configuration.width = Int(sourceRect.width * scale)
        configuration.height = Int(sourceRect.height * scale)
        configuration.captureResolution = resolution
        configuration.showsCursor = false
        configuration.ignoreShadowsSingleWindow = options.contains(.ignoreFraming)
        configuration.capturesShadowsOnly = options.contains(.onlyShadows)
        configuration.shouldBeOpaque = options.contains(.shouldBeOpaque)

        var result: Result<CGImage?, Error> = .success(nil)
        let semaphore = DispatchSemaphore(value: 0)

        SCScreenshotManager.captureImage(
            contentFilter: contentFilter,
            configuration: configuration
        ) { image, error in
            if let error {
                result = .failure(error)
            } else {
                result = .success(image)
            }
            semaphore.signal()
        }

        switch semaphore.wait(timeout: .now() + 1) {
        case .success:
            switch result {
            case .success(let image):
                return image
            case .failure(let error):
                Logger.windowCapture.error("Error capturing image: \(error)")
                return nil
            }
        case .timedOut:
            Logger.windowCapture.error("Error capturing image: Timed out")
            return nil
        }
    }

    private static func getDisplayScaleFactor(_ displayID: CGDirectDisplayID) -> CGFloat {
        guard let mode = CGDisplayCopyDisplayMode(displayID) else {
            return 1
        }
        return CGFloat(mode.pixelWidth) / CGFloat(mode.width)
    }
}

// MARK: - Logger
private extension Logger {
    static let windowCapture = mainSubsystem(category: "WindowCapture")
}
