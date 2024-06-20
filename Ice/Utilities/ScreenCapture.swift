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
        /// The provided display is invalid.
        case invalidDisplay

        /// The provided window is invalid.
        case invalidWindow

        /// The app does not have screen capture permissions.
        case missingPermissions

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
    ///   - window: The window to capture.
    ///   - captureRect: The rectangle to capture, relative to the coordinate space of the
    ///     window. Pass `nil` to capture the entire window.
    ///   - resolution: The resolution of the capture.
    ///   - options: Additional parameters for the capture.
    static func captureImage(
        window: WindowInfo,
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

        guard let currentWindow = WindowInfo(windowID: window.windowID) else {
            throw CaptureError.invalidWindow
        }

        let content = try await SCShareableContent.excludingDesktopWindows(
            false,
            onScreenWindowsOnly: currentWindow.isOnScreen
        )

        try Task.checkCancellation()

        guard let scWindow = content.windows.first(where: { $0.windowID == currentWindow.windowID }) else {
            throw CaptureError.invalidWindow
        }

        guard let scDisplay = content.displays.first(where: { $0.frame.contains(currentWindow.frame) }) else {
            throw CaptureError.invalidDisplay
        }

        let sourceRect = try getSourceRect(captureRect: captureRect, window: scWindow)
        let scaleFactor = try getScaleFactor(for: scDisplay, resolution: resolution)
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
    ///   - window: The window to capture.
    ///   - captureRect: The rectangle to capture, relative to the coordinate space of the
    ///     window. Pass `nil` to capture the entire window.
    ///   - resolution: The resolution of the capture.
    ///   - options: Additional parameters for the capture.
    static func captureImage(
        timeout: Duration,
        window: WindowInfo,
        captureRect: CGRect? = nil,
        resolution: SCCaptureResolutionType = .automatic,
        options: CaptureOptions = []
    ) async throws -> CGImage {
        let task = Task(timeout: timeout) {
            try await captureImage(
                window: window,
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
            CGRect(origin: .zero, size: captureRect.size)
        }
        guard windowBounds.contains(sourceRect) else {
            throw CaptureError.sourceRectOutOfBounds
        }
        return sourceRect
    }

    private static func getScaleFactor(for display: SCDisplay, resolution: SCCaptureResolutionType) throws -> CGFloat {
        if case .nominal = resolution {
            return 1
        }
        guard let mode = CGDisplayCopyDisplayMode(display.displayID) else {
            throw CaptureError.invalidDisplay
        }
        return CGFloat(mode.pixelWidth) / CGFloat(mode.width)
    }
}

extension ScreenCapture {
    /// Returns an image containing the area of the desktop wallpaper that is below the
    /// menu bar for the given display.
    static func desktopWallpaperBelowMenuBarScreenCaptureKit(
        display: CGDirectDisplayID,
        timeout: Duration
    ) async throws -> CGImage? {
        let task = Task(timeout: timeout) { () throws -> CGImage? in
            let windows = WindowInfo.getOnScreenWindows()
            guard
                let wallpaperWindow = WindowInfo.getWallpaperWindow(from: windows, for: display),
                let menuBarWindow = WindowInfo.getMenuBarWindow(from: windows, for: display)
            else {
                return nil
            }
            return try await captureImage(
                window: wallpaperWindow,
                captureRect: menuBarWindow.frame,
                options: .ignoreFraming
            )
        }
        return try await task.value
    }

    /// Returns an image containing the area of the desktop wallpaper that is below the
    /// menu bar for the given display.
    static func desktopWallpaperBelowMenuBarCoreGraphics(display: CGDirectDisplayID) -> CGImage? {
        let windows = WindowInfo.getOnScreenWindows()
        guard
            let wallpaperWindow = WindowInfo.getWallpaperWindow(from: windows, for: display),
            let menuBarWindow = WindowInfo.getMenuBarWindow(from: windows, for: display)
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
