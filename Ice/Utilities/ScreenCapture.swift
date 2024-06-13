//
//  ScreenCapture.swift
//  Ice
//

import Bridging
import ScreenCaptureKit

/// A namespace for screen capture operations.
enum ScreenCapture {
    /// Options that define additional parameters for a capture operation.
    struct CaptureOptions: OptionSet {
        let rawValue: Int

        /// If the `screenBounds` parameter of the capture is `nil`, captures only the window
        /// area and ignores the area occupied by any framing effects.
        static let ignoreFraming = CaptureOptions(rawValue: 1 << 0)

        /// Captures only the shadow effects of the provided windows.
        static let onlyShadows = CaptureOptions(rawValue: 1 << 1)

        /// Fills the partially or fully transparent areas of the capture with a solid white
        /// backing color, resulting in an image that is fully opaque.
        static let shouldBeOpaque = CaptureOptions(rawValue: 1 << 2)

        /// The cursor is shown in the capture.
        static let showsCursor = CaptureOptions(rawValue: 1 << 3)

        /// The output is scaled to fit the configured width and height.
        static let scalesToFit = CaptureOptions(rawValue: 1 << 4)
    }

    /// An error that can occur during a capture operation.
    enum CaptureError: Error {
        /// The app does not have screen capture permissions.
        case missingPermissions

        /// The screen capture manager cannot find a matching window.
        case noMatchingWindow

        /// The screen capture manager cannot find a matching display.
        case noMatchingDisplay

        /// There is no valid display mode for a display.
        case invalidDisplayMode

        /// The provided window is not on screen.
        case windowOffScreen

        /// The source rectangle of the capture is outside the bounds of the provided window.
        case sourceRectOutOfBounds

        /// The screen is in an invalid state for capture.
        case invalidScreenState(ScreenState)
    }

    /// A Boolean value that indicates whether the app has screen capture permissions.
    static var hasPermissions: Bool {
        CGPreflightScreenCaptureAccess()
    }

    /// Captures the given window as an image.
    ///
    /// - Parameters:
    ///   - window: The window to capture. The window must be on screen.
    ///   - captureRect: The rectangle to capture, relative to the coordinate space of the
    ///     window. Pass `nil` to capture the entire window.
    ///   - resolution: The resolution of the capture.
    ///   - options: Additional parameters for the capture.
    static func captureImage(
        onScreenWindow window: WindowInfo,
        captureRect: CGRect? = nil,
        resolution: SCCaptureResolutionType = .automatic,
        options: CaptureOptions = []
    ) async throws -> CGImage {
        guard hasPermissions else {
            throw CaptureError.missingPermissions
        }

        switch ScreenState.current {
        case .unlocked: break
        case let state: throw CaptureError.invalidScreenState(state)
        }

        let content = try await SCShareableContent.excludingDesktopWindows(
            false,
            onScreenWindowsOnly: true
        )

        try Task.checkCancellation()

        guard let scWindow = content.windows.first(where: { $0.windowID == window.windowID }) else {
            throw CaptureError.noMatchingWindow
        }

        guard let scDisplay = content.displays.first(where: { $0.frame.contains(window.frame) }) else {
            throw CaptureError.noMatchingDisplay
        }

        let sourceRect = try getSourceRect(captureRect: captureRect, window: scWindow)
        let scaleFactor = try getScaleFactor(for: scDisplay)
        let colorSpace = CGDisplayCopyColorSpace(scDisplay.displayID)

        let contentFilter = SCContentFilter(desktopIndependentWindow: scWindow)
        let configuration = SCStreamConfiguration()

        configuration.sourceRect = sourceRect
        configuration.width = Int(sourceRect.width * scaleFactor)
        configuration.height = Int(sourceRect.height * scaleFactor)
        configuration.captureResolution = resolution
        configuration.ignoreShadowsSingleWindow = options.contains(.ignoreFraming)
        configuration.capturesShadowsOnly = options.contains(.onlyShadows)
        configuration.shouldBeOpaque = options.contains(.shouldBeOpaque)
        configuration.showsCursor = options.contains(.showsCursor)
        configuration.scalesToFit = options.contains(.scalesToFit)

        if let colorSpaceName = colorSpace.name {
            configuration.colorSpaceName = colorSpaceName
        }

        let image = try await SCScreenshotManager.captureImage(
            contentFilter: contentFilter,
            configuration: configuration
        )

        try Task.checkCancellation()

        return image.copy(colorSpace: colorSpace) ?? image
    }

    /// Captures the given window as an image.
    ///
    /// - Parameters:
    ///   - timeout: The amount of time to wait before cancelling the task and throwing a
    ///     timeout error.
    ///   - window: The window to capture. The window must be on screen.
    ///   - captureRect: The rectangle to capture, relative to the coordinate space of the
    ///     window. Pass `nil` to capture the entire window.
    ///   - resolution: The resolution of the capture.
    ///   - options: Additional parameters for the capture.
    static func captureImage(
        timeout: Duration,
        onScreenWindow window: WindowInfo,
        captureRect: CGRect? = nil,
        resolution: SCCaptureResolutionType = .automatic,
        options: CaptureOptions = []
    ) async throws -> CGImage {
        let task = Task(timeout: timeout) {
            try await captureImage(
                onScreenWindow: window,
                captureRect: captureRect,
                resolution: resolution,
                options: options
            )
        }
        return try await task.value
    }

    private static func getSourceRect(captureRect: CGRect?, window: SCWindow) throws -> CGRect {
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
        return sourceRect
    }

    private static func getScaleFactor(for display: SCDisplay) throws -> CGFloat {
        guard let mode = CGDisplayCopyDisplayMode(display.displayID) else {
            throw CaptureError.invalidDisplayMode
        }
        return CGFloat(mode.pixelWidth) / CGFloat(mode.width)
    }
}

extension ScreenCapture {
    /// Returns an image containing the area of the desktop wallpaper that is below the
    /// menu bar for the given display.
    static func desktopWallpaperBelowMenuBar(for display: CGDirectDisplayID) -> CGImage? {
        guard
            let windows = try? WindowInfo.getOnScreenWindows(),
            let wallpaperWindow = try? WindowInfo.getWallpaperWindow(from: windows, for: display),
            let menuBarWindow = try? WindowInfo.getMenuBarWindow(from: windows, for: display)
        else {
            return nil
        }
        return Bridging.captureWindow(
            wallpaperWindow.windowID,
            screenBounds: menuBarWindow.frame,
            option: .boundsIgnoreFraming
        )
    }
}
