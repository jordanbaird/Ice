//
//  Bridging.swift
//  Bridging
//

package import CGSInternal
import CoreGraphics

/// A namespace for bridged functionality.
public enum Bridging { }

// MARK: - CGSConnection

extension Bridging {
    /// Sets a value for the given key in the current connection to the window server.
    ///
    /// - Parameters:
    ///   - value: The value to set for `key`.
    ///   - key: A key associated with the current connection to the window server.
    public static func setConnectionProperty(_ value: Any?, forKey key: String) {
        let result = CGSSetConnectionProperty(
            CGSMainConnectionID(),
            CGSMainConnectionID(),
            key as CFString,
            value as CFTypeRef
        )
        if result != .success {
            logger.error("CGSSetConnectionProperty failed with error \(result.rawValue)")
        }
    }

    /// Returns the value for the given key in the current connection to the window server.
    ///
    /// - Parameter key: A key associated with the current connection to the window server.
    /// - Returns: The value associated with `key` in the current connection to the window server.
    public static func getConnectionProperty(forKey key: String) -> Any? {
        var value: Unmanaged<CFTypeRef>?
        let result = CGSCopyConnectionProperty(
            CGSMainConnectionID(),
            CGSMainConnectionID(),
            key as CFString,
            &value
        )
        if result != .success {
            logger.error("CGSCopyConnectionProperty failed with error \(result.rawValue)")
        }
        return value?.takeRetainedValue()
    }
}

// MARK: - CGSWindow

extension Bridging {
    /// Returns the frame for the window with the specified identifier.
    ///
    /// - Parameter windowID: An identifier for a window.
    /// - Returns: The frame -- specified in screen coordinates -- of the window associated
    ///   with `windowID`, or `nil` if the operation failed.
    public static func getWindowFrame(for windowID: CGWindowID) -> CGRect? {
        var rect = CGRect.zero
        let result = CGSGetScreenRectForWindow(CGSMainConnectionID(), windowID, &rect)
        guard result == .success else {
            logger.error("CGSGetScreenRectForWindow failed with error \(result.rawValue)")
            return nil
        }
        return rect
    }
}

// MARK: Private Window List Helpers
extension Bridging {
    private static func getWindowCount() -> Int {
        var count: Int32 = 0
        let result = CGSGetWindowCount(CGSMainConnectionID(), 0, &count)
        if result != .success {
            logger.error("CGSGetWindowCount failed with error \(result.rawValue)")
        }
        return Int(count)
    }

    private static func getOnScreenWindowCount() -> Int {
        var count: Int32 = 0
        let result = CGSGetOnScreenWindowCount(CGSMainConnectionID(), 0, &count)
        if result != .success {
            logger.error("CGSGetOnScreenWindowCount failed with error \(result.rawValue)")
        }
        return Int(count)
    }

    private static func getWindowList() -> [CGWindowID] {
        let windowCount = getWindowCount()
        var list = [CGWindowID](repeating: 0, count: windowCount)
        var realCount: Int32 = 0
        let result = CGSGetWindowList(
            CGSMainConnectionID(),
            0,
            Int32(windowCount),
            &list,
            &realCount
        )
        guard result == .success else {
            logger.error("CGSGetWindowList failed with error \(result.rawValue)")
            return []
        }
        return [CGWindowID](list[..<Int(realCount)])
    }

    private static func getOnScreenWindowList() -> [CGWindowID] {
        let windowCount = getOnScreenWindowCount()
        var list = [CGWindowID](repeating: 0, count: windowCount)
        var realCount: Int32 = 0
        let result = CGSGetOnScreenWindowList(
            CGSMainConnectionID(),
            0,
            Int32(windowCount),
            &list,
            &realCount
        )
        guard result == .success else {
            logger.error("CGSGetOnScreenWindowList failed with error \(result.rawValue)")
            return []
        }
        return [CGWindowID](list[..<Int(realCount)])
    }

    private static func getMenuBarWindowList() -> [CGWindowID] {
        let windowCount = getWindowCount()
        var list = [CGWindowID](repeating: 0, count: windowCount)
        var realCount: Int32 = 0
        let result = CGSGetProcessMenuBarWindowList(
            CGSMainConnectionID(),
            0,
            Int32(windowCount),
            &list,
            &realCount
        )
        guard result == .success else {
            logger.error("CGSGetProcessMenuBarWindowList failed with error \(result.rawValue)")
            return []
        }
        return [CGWindowID](list[..<Int(realCount)])
    }

    private static func getOnScreenMenuBarWindowList() -> [CGWindowID] {
        let onScreenList = Set(getOnScreenWindowList())
        return getMenuBarWindowList().filter(onScreenList.contains)
    }
}

// MARK: Public Window List API
extension Bridging {
    /// Options that determine the window identifiers to return in a window list.
    public struct WindowListOption: OptionSet {
        public let rawValue: Int

        public init(rawValue: Int) {
            self.rawValue = rawValue
        }

        /// Specifies windows that are currently on-screen.
        public static let onScreen = WindowListOption(rawValue: 1 << 0)

        /// Specifies windows that represent items in the menu bar.
        public static let menuBarItems = WindowListOption(rawValue: 1 << 1)

        /// Specifies windows on the currently active space.
        public static let activeSpace = WindowListOption(rawValue: 1 << 2)
    }

    /// The total number of windows.
    public static var windowCount: Int {
        getWindowCount()
    }

    /// The number of windows currently on-screen.
    public static var onScreenWindowCount: Int {
        getOnScreenWindowCount()
    }

    /// Returns a list of window identifiers using the given options.
    ///
    /// - Parameter option: Options that filter the returned list.
    public static func getWindowList(option: WindowListOption = []) -> [CGWindowID] {
        let list = if option.contains(.menuBarItems) {
            if option.contains(.onScreen) {
                getOnScreenMenuBarWindowList()
            } else {
                getMenuBarWindowList()
            }
        } else if option.contains(.onScreen) {
            getOnScreenWindowList()
        } else {
            getWindowList()
        }
        return if option.contains(.activeSpace) {
            list.filter(isWindowOnActiveSpace)
        } else {
            list
        }
    }
}

// MARK: - CGSSpace

extension Bridging {
    /// The identifier of the active space.
    public static var activeSpaceID: Int {
        CGSGetActiveSpace(CGSMainConnectionID())
    }

    /// Returns a Boolean value that indicates whether the window with the
    /// given identifier is on the active space.
    ///
    /// - Parameter windowID: An identifier for a window.
    public static func isWindowOnActiveSpace(_ windowID: CGWindowID) -> Bool {
        guard let spaces = CGSCopySpacesForWindows(
            CGSMainConnectionID(),
            kCGSAllSpacesMask,
            [windowID] as CFArray
        ) else {
            logger.error("CGSCopySpacesForWindows failed")
            return false
        }
        guard let spaceIDs = spaces.takeRetainedValue() as? [CGSSpaceID] else {
            logger.error("CGSCopySpacesForWindows returned array of unexpected type")
            return false
        }
        return Set(spaceIDs).contains(activeSpaceID)
    }
}

extension Bridging {
    /// Captures an image of a window.
    ///
    /// - Parameters:
    ///   - windowID: The identifier of the window to capture.
    ///   - screenBounds: The on-screen bounds to capture.
    ///   - option: Options that specify the image to be captured.
    public static func captureWindow(
        _ windowID: CGWindowID,
        screenBounds: CGRect? = nil,
        option: CGWindowImageOption
    ) -> CGImage? {
        var pointer = UnsafeRawPointer(bitPattern: Int(windowID))
        guard
            let windowArray = CFArrayCreate(kCFAllocatorDefault, &pointer, 1, nil),
            let image = CGWindowListCreateImageFromArray(screenBounds ?? .null, windowArray, option)
        else {
            return nil
        }
        return image
    }
}

/// Returns a composite image of the specified windows.
///
/// This function links to a deprecated CoreGraphics function. We link to it this way to
/// silence the deprecation warning. Once ScreenCaptureKit can reliably capture offscreen
/// windows, this function should be removed.
///
/// See the documentation for the deprecated function here:
///
/// https://developer.apple.com/documentation/coregraphics/1455730-cgwindowlistcreateimagefromarray
@_silgen_name("CGWindowListCreateImageFromArray")
private func CGWindowListCreateImageFromArray(
    _ screenBounds: CGRect,
    _ windowArray: CFArray,
    _ imageOption: CGWindowImageOption
) -> CGImage?
