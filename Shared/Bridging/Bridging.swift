//
//  Bridging.swift
//  Shared
//

import Cocoa
import OSLog

// MARK: - Bridging

/// A namespace for bridged APIs.
enum Bridging {
    private static let mainConnectionID = CGSMainConnectionID()
    private static let logger = Logger(category: "Bridging")
}

// MARK: - CGSConnection

extension Bridging {
    /// Sets the value for a property in the app's window server connection.
    ///
    /// - Parameters:
    ///   - value: A value to set for `key`.
    ///   - key: A key for a property in the app's window server connection.
    static func setConnectionProperty(_ value: Any?, forKey key: String) {
        let result = CGSSetConnectionProperty(
            mainConnectionID,
            mainConnectionID,
            key as CFString,
            value as CFTypeRef
        )
        if result != .success {
            logger.error("CGSSetConnectionProperty failed with error \(result.logString, privacy: .public)")
        }
    }

    /// Returns the value for a property in the app's window server connection.
    ///
    /// - Parameter key: A key for a property in the app's window server connection.
    static func getConnectionProperty(forKey key: String) -> Any? {
        var value: Unmanaged<CFTypeRef>?
        let result = CGSCopyConnectionProperty(
            mainConnectionID,
            mainConnectionID,
            key as CFString,
            &value
        )
        if result != .success {
            logger.error("CGSCopyConnectionProperty failed with error \(result.logString, privacy: .public)")
        }
        return value?.takeRetainedValue()
    }
}

// MARK: - CGSEvent

extension Bridging {
    /// Returns a Boolean value indicating whether the given process is
    /// unresponsive.
    ///
    /// - Parameter pid: An identifier for a process.
    static func isProcessUnresponsive(_ pid: pid_t) -> Bool {
        var psn = ProcessSerialNumber()
        let result = GetProcessForPID(pid, &psn)
        guard result == noErr else {
            logger.error("GetProcessForPID failed with error \(result, privacy: .public)")
            return false
        }
        return CGSEventIsAppUnresponsive(mainConnectionID, &psn)
    }
}

// MARK: - CGSSpace

extension Bridging {
    /// Returns the identifier for the active space.
    static func getActiveSpaceID() -> CGSSpaceID {
        return CGSGetActiveSpace(mainConnectionID)
    }

    /// Returns the identifier for the current space on the given display.
    ///
    /// - Parameter displayID: An identifier for a display.
    static func getCurrentSpaceID(for displayID: CGDirectDisplayID) -> CGSSpaceID? {
        guard
            let uuid = CGDisplayCreateUUIDFromDisplayID(displayID),
            let uuidString = CFUUIDCreateString(nil, uuid.takeRetainedValue())
        else {
            logger.error("Failed to create UUID for display \(displayID, privacy: .public)")
            return nil
        }
        return CGSManagedDisplayGetCurrentSpace(mainConnectionID, uuidString)
    }

    /// Returns a list of identifiers for the spaces that contain the
    /// given window.
    ///
    /// - Parameters:
    ///   - windowID: An identifier for a window.
    ///   - visibleSpacesOnly: A Boolean value that determines whether
    ///     the returned list should only include visible spaces.
    ///     The default value is `false`.
    static func getSpaceList(for windowID: CGWindowID, visibleSpacesOnly: Bool = false) -> [CGSSpaceID] {
        let mask: CGSSpaceMask = visibleSpacesOnly ? .allVisibleSpacesMask : .allSpacesMask
        guard let spaces = CGSCopySpacesForWindows(mainConnectionID, mask, [windowID] as CFArray) else {
            logger.error("CGSCopySpacesForWindows returned nil")
            return []
        }
        guard let list = spaces.takeRetainedValue() as? [CGSSpaceID] else {
            logger.error("CGSCopySpacesForWindows returned array of unexpected type")
            return []
        }
        return list
    }

    /// Returns a Boolean value that indicates whether the given space
    /// is fullscreen.
    ///
    /// - Parameter spaceID: An identifier for a space.
    static func isSpaceFullscreen(_ spaceID: CGSSpaceID) -> Bool {
        let type = CGSSpaceGetType(mainConnectionID, spaceID)
        return type == .fullscreen
    }

    /// Returns a Boolean value that indicates whether the active space
    /// is fullscreen.
    static func isActiveSpaceFullscreen() -> Bool {
        let activeSpaceID = getActiveSpaceID()
        return isSpaceFullscreen(activeSpaceID)
    }
}

// MARK: - CGSWindow

extension Bridging {
    /// Returns the bounds for the given window.
    ///
    /// - Parameter windowID: An identifier for a window.
    static func getWindowBounds(for windowID: CGWindowID) -> CGRect? {
        var bounds = CGRect.zero
        let result = CGSGetWindowBounds(mainConnectionID, windowID, &bounds)
        guard result == .success else {
            logger.error("CGSGetWindowBounds failed with error \(result.logString, privacy: .public)")
            return nil
        }
        return bounds
    }

    /// Returns the level for the given window.
    ///
    /// - Parameter windowID: An identifier for a window.
    static func getWindowLevel(for windowID: CGWindowID) -> CGWindowLevel? {
        var level: CGWindowLevel = 0
        let result = CGSGetWindowLevel(mainConnectionID, windowID, &level)
        guard result == .success else {
            logger.error("CGSGetWindowLevel failed with error \(result.logString, privacy: .public)")
            return nil
        }
        return level
    }

    /// Returns a Boolean value that indicates whether the given window
    /// is on the given space.
    ///
    /// - Parameters:
    ///   - windowID: An identifier for a window.
    ///   - spaceID: An identifier for a space.
    static func isWindowOnSpace(_ windowID: CGWindowID, _ spaceID: CGSSpaceID) -> Bool {
        let list = getSpaceList(for: windowID, visibleSpacesOnly: false)
        return list.contains(spaceID)
    }

    /// Returns a Boolean value that indicates whether the given window
    /// is on the active space.
    ///
    /// - Parameter windowID: An identifier for a window.
    static func isWindowOnActiveSpace(_ windowID: CGWindowID) -> Bool {
        let activeSpaceID = getActiveSpaceID()
        return isWindowOnSpace(windowID, activeSpaceID)
    }

    /// Returns a Boolean value that indicates whether the given window
    /// intersects the given display bounds.
    ///
    /// - Parameters:
    ///   - windowID: An identifier for a window.
    ///   - displayBounds: The bounds of a display.
    static func windowIntersectsDisplayBounds(_ windowID: CGWindowID, _ displayBounds: CGRect) -> Bool {
        if let windowBounds = getWindowBounds(for: windowID) {
            return displayBounds.intersects(windowBounds)
        }
        return false
    }

    /// Returns a Boolean value that indicates whether the given window
    /// is on the specified display.
    ///
    /// - Parameters:
    ///   - windowID: An identifier for a window.
    ///   - displayID: An identifier for a display.
    static func isWindowOnDisplay(_ windowID: CGWindowID, _ displayID: CGDirectDisplayID) -> Bool {
        let displayBounds = CGDisplayBounds(displayID)
        return windowIntersectsDisplayBounds(windowID, displayBounds)
    }

    // MARK: Private Window List Helpers

    private static func getFullWindowCount() -> Int32 {
        var count: Int32 = 0
        let result = CGSGetWindowCount(mainConnectionID, 0, &count)
        if result != .success {
            logger.error("CGSGetWindowCount failed with error \(result.logString, privacy: .public)")
        }
        return count
    }

    private static func getOnScreenWindowCount() -> Int32 {
        var count: Int32 = 0
        let result = CGSGetOnScreenWindowCount(mainConnectionID, 0, &count)
        if result != .success {
            logger.error("CGSGetOnScreenWindowCount failed with error \(result.logString, privacy: .public)")
        }
        return count
    }

    private static func getFullWindowList() -> [CGWindowID] {
        let count = getFullWindowCount()
        var list = [CGWindowID](repeating: 0, count: Int(count))
        var outCount: Int32 = 0
        let result = CGSGetWindowList(mainConnectionID, 0, count, &list, &outCount)
        guard result == .success else {
            logger.error("CGSGetWindowList failed with error \(result.logString, privacy: .public)")
            return []
        }
        return [CGWindowID](list[..<Int(outCount)])
    }

    private static func getOnScreenWindowList() -> [CGWindowID] {
        let count = getOnScreenWindowCount()
        var list = [CGWindowID](repeating: 0, count: Int(count))
        var outCount: Int32 = 0
        let result = CGSGetOnScreenWindowList(mainConnectionID, 0, count, &list, &outCount)
        guard result == .success else {
            logger.error("CGSGetOnScreenWindowList failed with error \(result.logString, privacy: .public)")
            return []
        }
        return [CGWindowID](list[..<Int(outCount)])
    }

    private static func getFullMenuBarWindowList() -> [CGWindowID] {
        let count = getFullWindowCount()
        var list = [CGWindowID](repeating: 0, count: Int(count))
        var outCount: Int32 = 0
        let result = CGSGetProcessMenuBarWindowList(mainConnectionID, 0, count, &list, &outCount)
        guard result == .success else {
            logger.error("CGSGetProcessMenuBarWindowList failed with error \(result.logString, privacy: .public)")
            return []
        }
        return [CGWindowID](list[..<Int(outCount)])
    }

    // MARK: Public Window List API

    /// Options that specify the identifiers in a window list.
    struct WindowListOption: OptionSet {
        let rawValue: Int

        /// Specifies windows that are currently on screen.
        static let onScreen = WindowListOption(rawValue: 1 << 0)

        /// Specifies windows on the currently active space.
        static let activeSpace = WindowListOption(rawValue: 1 << 1)
    }

    /// Options that specify the identifiers in a menu bar window list.
    struct MenuBarWindowListOption: OptionSet {
        let rawValue: Int

        /// Specifies windows that are currently on screen.
        static let onScreen = MenuBarWindowListOption(rawValue: 1 << 0)

        /// Specifies windows on the currently active space.
        static let activeSpace = MenuBarWindowListOption(rawValue: 1 << 1)

        /// Specifies only windows that represent menu bar items.
        static let itemsOnly = MenuBarWindowListOption(rawValue: 1 << 2)
    }

    /// Returns a list of window identifiers.
    ///
    /// - Parameter option: Options that filter the returned list.
    ///   Pass an empty option set to return all available windows.
    static func getWindowList(option: WindowListOption = []) -> [CGWindowID] {
        let list = if option.contains(.onScreen) {
            getOnScreenWindowList()
        } else {
            getFullWindowList()
        }
        if option.contains(.activeSpace) {
            let activeSpaceID = getActiveSpaceID()
            return list.filter { windowID in
                isWindowOnSpace(windowID, activeSpaceID)
            }
        }
        return list
    }

    /// Returns a list of window identifiers for elements in the
    /// menu bar.
    ///
    /// - Parameter option: Options that filter the returned list.
    ///   Pass an empty option set to return all available windows.
    static func getMenuBarWindowList(option: MenuBarWindowListOption = []) -> [CGWindowID] {
        var predicates = [(CGWindowID) -> Bool]()

        if option.contains(.onScreen) {
            let onScreenList = Set(getOnScreenWindowList())
            predicates.append { windowID in
                onScreenList.contains(windowID)
            }
        }

        if option.contains(.activeSpace) {
            let activeSpaceID = getActiveSpaceID()
            predicates.append { windowID in
                isWindowOnSpace(windowID, activeSpaceID)
            }
        }

        if option.contains(.itemsOnly) {
            predicates.append { windowID in
                getWindowLevel(for: windowID) != kCGMainMenuWindowLevel
            }
        }

        return getFullMenuBarWindowList().filter { windowID in
            predicates.allSatisfy { predicate in
                predicate(windowID)
            }
        }
    }

    // MARK: - CGWindowList Specific

    /// Creates a `CFArray` containing the bit patterns of the given
    /// window list.
    ///
    /// Pass the returned array into one of the `CGWindowList` APIs
    /// from `CoreGraphics`.
    ///
    /// - Parameter windowIDs: A list of window identifiers. If the
    ///   list is empty, or if none of its elements can represent a
    ///   valid bit pattern, this function returns `nil`.
    ///
    /// - Returns: A `CFArray` where each element is a memory address
    ///   with a bit pattern that matches an element from `windowIDs`,
    ///   or `nil` if the array cannot be created.
    static func createCGWindowArray(with windowIDs: [CGWindowID]) -> CFArray? {
        var pointers: [UnsafeRawPointer?] = windowIDs.compactMap { windowID in
            UnsafeRawPointer(bitPattern: UInt(windowID))
        }
        guard
            !pointers.isEmpty,
            let array = CFArrayCreate(nil, &pointers, pointers.count, nil)
        else {
            return nil
        }
        return array
    }
}
