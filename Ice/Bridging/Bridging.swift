//
//  Bridging.swift
//  Ice
//

import Cocoa

/// A namespace for bridged functionality.
enum Bridging {
    private static let mainConnectionID = CGSMainConnectionID()
    private static let logger = Logger(category: "Bridging")
}

// MARK: - CGSConnection

extension Bridging {
    /// Sets a value for the given key in the app's connection to
    /// the window server.
    ///
    /// - Parameters:
    ///   - value: The value to set for `key`.
    ///   - key: A key associated with the app's connection to the
    ///     window server.
    static func setConnectionProperty(_ value: Any?, forKey key: String) {
        let result = CGSSetConnectionProperty(
            mainConnectionID,
            mainConnectionID,
            key as CFString,
            value as CFTypeRef
        )
        if result != .success {
            logger.error("CGSSetConnectionProperty failed with error \(result.logString)")
        }
    }

    /// Returns the value for the given key in the app's connection
    /// to the window server.
    ///
    /// - Parameter key: A key associated with the app's connection
    ///   to the window server.
    static func getConnectionProperty(forKey key: String) -> Any? {
        var value: Unmanaged<CFTypeRef>?
        let result = CGSCopyConnectionProperty(
            mainConnectionID,
            mainConnectionID,
            key as CFString,
            &value
        )
        if result != .success {
            logger.error("CGSCopyConnectionProperty failed with error \(result.logString)")
        }
        return value?.takeRetainedValue()
    }
}

// MARK: - CGSWindow

extension Bridging {
    /// Returns the frame, specified in screen coordinates, for the
    /// window with the specified identifier.
    ///
    /// - Parameter windowID: An identifier for a window.
    static func getWindowFrame(for windowID: CGWindowID) -> CGRect? {
        var rect = CGRect.zero
        let result = CGSGetScreenRectForWindow(mainConnectionID, windowID, &rect)
        guard result == .success else {
            logger.error("CGSGetScreenRectForWindow failed with error \(result.logString)")
            return nil
        }
        return rect
    }

    /// Returns the level for the window with the specified identifier.
    ///
    /// - Parameter windowID: An identifier for a window.
    static func getWindowLevel(for windowID: CGWindowID) -> CGWindowLevel? {
        var level: CGWindowLevel = 0
        let result = CGSGetWindowLevel(mainConnectionID, windowID, &level)
        guard result == .success else {
            logger.error("CGSGetWindowLevel failed with error \(result.logString)")
            return nil
        }
        return level
    }
}

// MARK: Private Window List Helpers
extension Bridging {
    private static func getWindowCount() -> Int {
        var count: Int32 = 0
        let result = CGSGetWindowCount(mainConnectionID, 0, &count)
        if result != .success {
            logger.error("CGSGetWindowCount failed with error \(result.logString)")
        }
        return Int(count)
    }

    private static func getOnScreenWindowCount() -> Int {
        var count: Int32 = 0
        let result = CGSGetOnScreenWindowCount(mainConnectionID, 0, &count)
        if result != .success {
            logger.error("CGSGetOnScreenWindowCount failed with error \(result.logString)")
        }
        return Int(count)
    }

    private static func getWindowList() -> [CGWindowID] {
        let windowCount = getWindowCount()
        var list = [CGWindowID](repeating: 0, count: windowCount)
        var realCount: Int32 = 0
        let result = CGSGetWindowList(
            mainConnectionID,
            0,
            Int32(windowCount),
            &list,
            &realCount
        )
        guard result == .success else {
            logger.error("CGSGetWindowList failed with error \(result.logString)")
            return []
        }
        return [CGWindowID](list[..<Int(realCount)])
    }

    private static func getOnScreenWindowList() -> [CGWindowID] {
        let windowCount = getOnScreenWindowCount()
        var list = [CGWindowID](repeating: 0, count: windowCount)
        var realCount: Int32 = 0
        let result = CGSGetOnScreenWindowList(
            mainConnectionID,
            0,
            Int32(windowCount),
            &list,
            &realCount
        )
        guard result == .success else {
            logger.error("CGSGetOnScreenWindowList failed with error \(result.logString)")
            return []
        }
        return [CGWindowID](list[..<Int(realCount)])
    }

    private static func getMenuBarItemWindowList() -> [CGWindowID] {
        let windowCount = getWindowCount()
        var list = [CGWindowID](repeating: 0, count: windowCount)
        var realCount: Int32 = 0
        let result = CGSGetProcessMenuBarWindowList(
            mainConnectionID,
            0,
            Int32(windowCount),
            &list,
            &realCount
        )
        guard result == .success else {
            logger.error("CGSGetProcessMenuBarWindowList failed with error \(result.logString)")
            return []
        }
        return list[..<Int(realCount)].filter { windowID in
            let level = getWindowLevel(for: windowID)
            return level != kCGMainMenuWindowLevel
        }
    }

    private static func getOnScreenMenuBarItemWindowList() -> [CGWindowID] {
        let onScreenList = Set(getOnScreenWindowList())
        return getMenuBarItemWindowList().filter(onScreenList.contains)
    }
}

// MARK: Public Window List API
extension Bridging {
    /// Options that specify the identifiers in a window list.
    struct WindowListOption: OptionSet {
        let rawValue: Int

        /// Specifies windows that are currently on-screen.
        static let onScreen = WindowListOption(rawValue: 1 << 0)

        /// Specifies windows that represent items in the menu bar.
        static let menuBarItems = WindowListOption(rawValue: 1 << 1)

        /// Specifies windows on the currently active space.
        static let activeSpace = WindowListOption(rawValue: 1 << 2)
    }

    /// Returns a list of window identifiers using the given options.
    ///
    /// - Parameter option: Options that filter the returned list.
    ///   Pass an empty option set to return all available windows.
    static func getWindowList(option: WindowListOption = []) -> [CGWindowID] {
        let list = if option.contains(.menuBarItems) {
            if option.contains(.onScreen) {
                getOnScreenMenuBarItemWindowList()
            } else {
                getMenuBarItemWindowList()
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
    /// Options that specify the identifiers in a space list.
    enum SpaceListOption {
        /// Specifies all available spaces.
        case allSpaces

        /// Specifies visible spaces.
        case visibleSpaces
    }

    /// Returns the identifier for the current active space.
    static func getActiveSpaceID() -> CGSSpaceID {
        return CGSGetActiveSpace(mainConnectionID)
    }

    /// Returns the identifier for the current space on the given
    /// display.
    ///
    /// - Parameter displayID: An identifier for a display.
    static func getCurrentSpaceID(for displayID: CGDirectDisplayID) -> CGSSpaceID? {
        guard
            let uuid = CGDisplayCreateUUIDFromDisplayID(displayID),
            let uuidString = CFUUIDCreateString(nil, uuid.takeRetainedValue())
        else {
            return nil
        }
        return CGSManagedDisplayGetCurrentSpace(mainConnectionID, uuidString)
    }

    /// Returns a list of identifiers for the spaces that contain
    /// the given window.
    ///
    /// - Parameters:
    ///   - windowID: An identifier for a window.
    ///   - option: An option that filters the spaces included in
    ///     the returned list.
    static func getSpaceList(for windowID: CGWindowID, option: SpaceListOption) -> [CGSSpaceID] {
        let mask: CGSSpaceMask = switch option {
        case .allSpaces: .allSpaces
        case .visibleSpaces: .allVisibleSpaces
        }
        guard let spaces = CGSCopySpacesForWindows(mainConnectionID, mask, [windowID] as CFArray) else {
            logger.error("CGSCopySpacesForWindows returned nil value")
            return []
        }
        guard let list = spaces.takeRetainedValue() as? [CGSSpaceID] else {
            logger.error("CGSCopySpacesForWindows returned array of unexpected type")
            return []
        }
        return list
    }

    /// Returns a Boolean value that indicates whether the window
    /// with the given identifier is on the specified space.
    ///
    /// - Parameters:
    ///   - windowID: An identifier for a window.
    ///   - spaceID: An identifier for a space.
    static func isWindowOnSpace(_ windowID: CGWindowID, _ spaceID: CGSSpaceID) -> Bool {
        let list = getSpaceList(for: windowID, option: .allSpaces)
        return list.contains(spaceID)
    }

    /// Returns a Boolean value that indicates whether the window
    /// with the given identifier is on the current active space.
    ///
    /// - Parameter windowID: An identifier for a window.
    static func isWindowOnActiveSpace(_ windowID: CGWindowID) -> Bool {
        let spaceID = getActiveSpaceID()
        return isWindowOnSpace(windowID, spaceID)
    }

    /// Returns a Boolean value that indicates whether the space
    /// with the given identifier is fullscreen.
    ///
    /// - Parameter spaceID: An identifier for a space.
    static func isSpaceFullscreen(_ spaceID: CGSSpaceID) -> Bool {
        let type = CGSSpaceGetType(mainConnectionID, spaceID)
        return type == .fullscreen
    }

    /// Returns a Boolean value that indicates whether the current
    /// active space is fullscreen.
    static func isActiveSpaceFullscreen() -> Bool {
        let spaceID = getActiveSpaceID()
        return isSpaceFullscreen(spaceID)
    }
}

// MARK: - Process Responsivity

extension Bridging {
    /// Constants that indicate the responsivity of a process.
    enum Responsivity {
        /// The process is known to be responsive.
        case responsive

        /// The process is known to be unresponsive.
        case unresponsive

        /// The responsivity of the process is unknown.
        case unknown
    }

    /// Returns the responsivity of the given process.
    ///
    /// - Parameter pid: An identifier for a process.
    static func responsivity(for pid: pid_t) -> Responsivity {
        var psn = ProcessSerialNumber()
        let result = GetProcessForPID(pid, &psn)
        guard result == noErr else {
            logger.error("GetProcessForPID failed with error \(result)")
            return .unknown
        }
        if CGSEventIsAppUnresponsive(mainConnectionID, &psn) {
            return .unresponsive
        }
        return .responsive
    }
}
