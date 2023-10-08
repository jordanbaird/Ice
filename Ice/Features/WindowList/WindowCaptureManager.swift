//
//  WindowCaptureManager.swift
//  Ice
//

import ScreenCaptureKit

/// A type that manages the capturing of window images.
class WindowCaptureManager {
    /// The resolution at which to capture a window or group of windows.
    enum CaptureResolution {
        /// Windows are captured at the best possible resolution.
        case best
        /// Windows are captured at the nominal resolution.
        case nominal
        /// Capture resolution is determined automatically.
        case automatic
    }

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
        static let opaque = CaptureOptions(rawValue: 1 << 2)
    }

    /// Captures the given windows as a composite image.
    ///
    /// - Parameters:
    ///   - windows: The windows to capture as a composite image.
    ///   - screenBounds: The bounds to capture, specified in screen coordinates,
    ///     with the origin at the upper left corner of the main display. Pass `nil`
    ///     to capture the minimum area enclosing `windows`.
    ///   - resolution: The resolution at which to capture the windows.
    ///   - options: Options that affect the image returned from the capture.
    static func captureImage(
        windows: [SCWindow],
        screenBounds: CGRect? = nil,
        resolution: CaptureResolution = .automatic,
        options: CaptureOptions = []
    ) -> CGImage? {
        let count = windows.count
        let pointer = UnsafeMutablePointer<UnsafeRawPointer?>.allocate(capacity: count)
        for (index, window) in windows.enumerated() {
            pointer[index] = UnsafeRawPointer(bitPattern: UInt(window.windowID))
        }
        guard let windowArray = CFArrayCreate(kCFAllocatorDefault, pointer, count, nil) else {
            return nil
        }
        var imageOption: CGWindowImageOption = []
        switch resolution {
        case .best:
            imageOption.insert(.bestResolution)
        case .nominal:
            imageOption.insert(.nominalResolution)
        case .automatic:
            break
        }
        if options.contains(.ignoreFraming) {
            imageOption.insert(.boundsIgnoreFraming)
        }
        if options.contains(.onlyShadows) {
            imageOption.insert(.onlyShadows)
        }
        if options.contains(.opaque) {
            imageOption.insert(.shouldBeOpaque)
        }
        return CGImage(
            windowListFromArrayScreenBounds: screenBounds ?? .null,
            windowArray: windowArray,
            imageOption: imageOption
        )
    }
}
