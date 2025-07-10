//
//  Bridging.swift
//  Ice
//

import Cocoa
import OSLog

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
            logger.error("CGSSetConnectionProperty failed with error \(result.logString, privacy: .public)")
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
            logger.error("CGSCopyConnectionProperty failed with error \(result.logString, privacy: .public)")
        }
        return value?.takeRetainedValue()
    }
}

// MARK: - CGSWindow

extension Bridging {
    /// Returns the bounds for the window with the specified identifier.
    ///
    /// - Parameter windowID: An identifier for a window.
    static func getWindowBounds(for windowID: CGWindowID) -> CGRect? {
        var bounds = CGRect.zero
        if #available(macOS 26.0, *) {
            let result = CGSGetWindowBounds(mainConnectionID, windowID, &bounds)
            guard result == .success else {
                logger.error("CGSGetWindowBounds failed with error \(result.logString, privacy: .public)")
                return nil
            }
        } else {
            let result = CGSGetScreenRectForWindow(mainConnectionID, windowID, &bounds)
            guard result == .success else {
                logger.error("CGSGetScreenRectForWindow failed with error \(result.logString, privacy: .public)")
                return nil
            }
        }
        return bounds
    }

    /// Returns the level for the window with the specified identifier.
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

    /// Returns a Boolean value that indicates whether the window
    /// with the given identifier is on the specified display.
    ///
    /// - Parameters:
    ///   - windowID: An identifier for a window.
    ///   - displayID: An identifier for a display.
    static func isWindowOnDisplay(_ windowID: CGWindowID, _ displayID: CGDirectDisplayID) -> Bool {
        if let windowBounds = getWindowBounds(for: windowID) {
            let displayBounds = CGDisplayBounds(displayID)
            return displayBounds.intersects(windowBounds)
        }
        return false
    }
}

// MARK: Private Window List Helpers
extension Bridging {
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
}

// MARK: Public Window List API
extension Bridging {
    /// Options that specify the identifiers in a window list.
    struct WindowListOption: OptionSet {
        let rawValue: Int

        /// Specifies windows that are currently on-screen.
        static let onScreen = WindowListOption(rawValue: 1 << 0)

        /// Specifies windows on the currently active space.
        static let activeSpace = WindowListOption(rawValue: 1 << 1)
    }

    /// Options that specify the identifiers included in a menu bar window list.
    struct MenuBarWindowListOption: OptionSet {
        let rawValue: Int

        /// Specifies windows that are currently on-screen.
        static let onScreen = MenuBarWindowListOption(rawValue: 1 << 0)

        /// Specifies windows on the currently active space.
        static let activeSpace = MenuBarWindowListOption(rawValue: 1 << 1)

        /// Specifies only windows that represent menu bar items.
        static let itemsOnly = MenuBarWindowListOption(rawValue: 1 << 2)
    }

    /// Returns a list of window identifiers using the given options.
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

    /// Returns a list of window identifiers representing elements
    /// of the menu bar.
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

    /// Creates a `CFArray` containing the bit patterns of the given
    /// list of window identifiers.
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
            logger.error("GetProcessForPID failed with error \(result, privacy: .public)")
            return .unknown
        }
        if CGSEventIsAppUnresponsive(mainConnectionID, &psn) {
            return .unresponsive
        }
        return .responsive
    }
}
