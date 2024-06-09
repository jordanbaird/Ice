//
//  WindowInfo.swift
//  Ice
//

import Bridging
import Cocoa

/// Information for a window.
struct WindowInfo {
    /// The window identifier associated with the window.
    let windowID: CGWindowID

    /// The frame of the window.
    ///
    /// The frame is specified in screen coordinates, where the origin
    /// is at the upper left corner of the main display.
    let frame: CGRect

    /// The title of the window.
    let title: String?

    /// The layer number of the window.
    let layer: Int

    /// The alpha value of the window, ranging from `0.0` to `1.0`,
    /// where `0.0` is fully transparent, and `1.0` is fully opaque.
    let alpha: Double

    /// The process identifier of the application that owns the window.
    let ownerPID: pid_t

    /// The name of the application that owns the window.
    ///
    /// This may have a value when ``owningApplication`` does not have a
    /// localized name.
    let ownerName: String?

    /// The sharing mode used by the window.
    let sharingState: CGWindowSharingType

    /// The backing type of the window.
    let backingStoreType: CGWindowBackingType

    /// An estimate of the amount of memory in bytes used by the window.
    let memoryUsage: Measurement<UnitInformationStorage>

    /// A Boolean value that indicates whether the window is on screen.
    let isOnScreen: Bool

    /// A Boolean value that indicates whether the window's backing store
    /// is located in video memory.
    let isBackedByVideoMemory: Bool

    /// The application that owns the window.
    var owningApplication: NSRunningApplication? {
        NSRunningApplication(processIdentifier: ownerPID)
    }

    /// A Boolean value that indicates whether the window represents a
    /// menu bar item.
    var isMenuBarItem: Bool {
        layer == kCGStatusWindowLevel
    }

    /// A Boolean value that indicates whether the window belongs to the
    /// window server.
    var isWindowServerWindow: Bool {
        ownerName == "Window Server"
    }

    /// A Boolean value that indicates whether the window is on the active space.
    var isOnActiveSpace: Bool {
        Bridging.isWindowOnActiveSpace(windowID)
    }

    /// Creates a window with the given dictionary.
    private init?(dictionary: CFDictionary) {
        guard
            let info = dictionary as? [CFString: CFTypeRef],
            let windowID = info[kCGWindowNumber] as? CGWindowID,
            let boundsDict = info[kCGWindowBounds] as? NSDictionary,
            let frame = CGRect(dictionaryRepresentation: boundsDict),
            let layer = info[kCGWindowLayer] as? Int,
            let alpha = info[kCGWindowAlpha] as? Double,
            let ownerPID = info[kCGWindowOwnerPID] as? pid_t,
            let rawSharingState = info[kCGWindowSharingState] as? UInt32,
            let rawBackingStoreType = info[kCGWindowStoreType] as? UInt32,
            let sharingState = CGWindowSharingType(rawValue: rawSharingState),
            let backingStoreType = CGWindowBackingType(rawValue: rawBackingStoreType),
            let memoryUsage = info[kCGWindowMemoryUsage] as? Double
        else {
            return nil
        }
        self.windowID = windowID
        self.frame = frame
        self.title = info[kCGWindowName] as? String
        self.layer = layer
        self.alpha = alpha
        self.ownerPID = ownerPID
        self.ownerName = info[kCGWindowOwnerName] as? String
        self.sharingState = sharingState
        self.backingStoreType = backingStoreType
        self.memoryUsage = Measurement(value: memoryUsage, unit: .bytes)
        self.isOnScreen = info[kCGWindowIsOnscreen] as? Bool ?? false
        self.isBackedByVideoMemory = info[kCGWindowBackingLocationVideoMemory] as? Bool ?? false
    }

    /// Creates a window with the given window identifier.
    init?(windowID: CGWindowID) {
        var pointer = UnsafeRawPointer(bitPattern: Int(windowID))
        guard
            let array = CFArrayCreate(kCFAllocatorDefault, &pointer, 1, nil),
            let list = CGWindowListCreateDescriptionFromArray(array) as? [CFDictionary],
            let dictionary = list.first
        else {
            return nil
        }
        self.init(dictionary: dictionary)
    }
}

// MARK: - WindowList Operations

extension WindowInfo {

    // MARK: WindowListError

    /// An error that can be thrown during window list operations.
    enum WindowListError: Error {
        /// Indicates that copying the window list failed.
        case cannotCopyWindowList
        /// Indicates that the desired window is not present in the list.
        case noMatchingWindow
    }
}

// MARK: Private
extension WindowInfo {
    /// Options to use to retrieve on screen windows.
    private enum OnScreenWindowListOption {
        case above(_ window: WindowInfo, includeWindow: Bool)
        case below(_ window: WindowInfo, includeWindow: Bool)
        case onScreenOnly
    }

    /// A context that contains the information needed to retrieve a window list.
    private struct WindowListContext {
        let windowListOption: CGWindowListOption
        let referenceWindow: WindowInfo?

        init(windowListOption: CGWindowListOption, referenceWindow: WindowInfo?) {
            self.windowListOption = windowListOption
            self.referenceWindow = referenceWindow
        }

        init(onScreenOption: OnScreenWindowListOption, excludeDesktopWindows: Bool) {
            var windowListOption: CGWindowListOption = []
            var referenceWindow: WindowInfo?
            switch onScreenOption {
            case .above(let window, let includeWindow):
                windowListOption.insert(.optionOnScreenAboveWindow)
                if includeWindow {
                    windowListOption.insert(.optionIncludingWindow)
                }
                referenceWindow = window
            case .below(let window, let includeWindow):
                windowListOption.insert(.optionOnScreenBelowWindow)
                if includeWindow {
                    windowListOption.insert(.optionIncludingWindow)
                }
                referenceWindow = window
            case .onScreenOnly:
                windowListOption.insert(.optionOnScreenOnly)
            }
            if excludeDesktopWindows {
                windowListOption.insert(.excludeDesktopElements)
            }
            self.init(windowListOption: windowListOption, referenceWindow: referenceWindow)
        }
    }

    /// Retrieves a copy of the current window list as an array of dictionaries.
    private static func copyWindowListArray(context: WindowListContext) throws -> [CFDictionary] {
        let option = context.windowListOption
        let windowID = context.referenceWindow?.windowID ?? kCGNullWindowID
        guard let list = CGWindowListCopyWindowInfo(option, windowID) as? [CFDictionary] else {
            throw WindowListError.cannotCopyWindowList
        }
        return list
    }

    /// Returns the current window list using the given context.
    private static func getWindowList(context: WindowListContext) throws -> [WindowInfo] {
        let list = try copyWindowListArray(context: context)
        return list.compactMap { WindowInfo(dictionary: $0) }
    }
}

// MARK: All Windows
extension WindowInfo {
    /// Returns the current windows.
    ///
    /// - Parameter excludeDesktopWindows: A Boolean value that indicates whether
    ///   to exclude desktop owned windows, such as the wallpaper and desktop icons.
    static func getAllWindows(excludeDesktopWindows: Bool = false) throws -> [WindowInfo] {
        var option = CGWindowListOption.optionAll
        if excludeDesktopWindows {
            option.insert(.excludeDesktopElements)
        }
        let context = WindowListContext(windowListOption: option, referenceWindow: nil)
        return try getWindowList(context: context)
    }
}

// MARK: On Screen Windows
extension WindowInfo {
    /// Returns the on screen windows.
    ///
    /// - Parameter excludeDesktopWindows: A Boolean value that indicates whether
    ///   to exclude desktop owned windows, such as the wallpaper and desktop icons.
    static func getOnScreenWindows(excludeDesktopWindows: Bool = false) throws -> [WindowInfo] {
        let context = WindowListContext(
            onScreenOption: .onScreenOnly,
            excludeDesktopWindows: excludeDesktopWindows
        )
        return try getWindowList(context: context)
    }

    /// Returns the on screen windows above the given window.
    ///
    /// - Parameters:
    ///   - window: The window to use as a reference point when determining which
    ///     windows to return.
    ///   - includeWindow: A Boolean value that indicates whether to include the
    ///     window in the result.
    ///   - excludeDesktopWindows: A Boolean value that indicates whether to exclude
    ///     desktop owned windows, such as the wallpaper and desktop icons.
    static func getOnScreenWindows(
        above window: WindowInfo,
        includeWindow: Bool = false,
        excludeDesktopWindows: Bool = false
    ) throws -> [WindowInfo] {
        let context = WindowListContext(
            onScreenOption: .above(window, includeWindow: includeWindow),
            excludeDesktopWindows: excludeDesktopWindows
        )
        return try getWindowList(context: context)
    }

    /// Returns the on screen windows below the given window.
    ///
    /// - Parameters:
    ///   - window: The window to use as a reference point when determining which
    ///     windows to return.
    ///   - includeWindow: A Boolean value that indicates whether to include the
    ///     window in the result.
    ///   - excludeDesktopWindows: A Boolean value that indicates whether to exclude
    ///     desktop owned windows, such as the wallpaper and desktop icons.
    static func getOnScreenWindows(
        below window: WindowInfo,
        includeWindow: Bool = false,
        excludeDesktopWindows: Bool = false
    ) throws -> [WindowInfo] {
        let context = WindowListContext(
            onScreenOption: .below(window, includeWindow: includeWindow),
            excludeDesktopWindows: excludeDesktopWindows
        )
        return try getWindowList(context: context)
    }
}

// MARK: Wallpaper Window
extension WindowInfo {
    /// Returns the wallpaper window in the given windows for the given display.
    static func getWallpaperWindow(from windows: [WindowInfo], for display: CGDirectDisplayID) throws -> WindowInfo {
        guard let window = windows.first(where: Predicates.wallpaperWindow(for: display)) else {
            throw WindowListError.noMatchingWindow
        }
        return window
    }

    /// Returns the wallpaper window for the given display.
    static func getWallpaperWindow(for display: CGDirectDisplayID) throws -> WindowInfo {
        try getWallpaperWindow(from: getOnScreenWindows(), for: display)
    }
}

// MARK: Menu Bar Window
extension WindowInfo {
    /// Returns the menu bar window for the given display.
    static func getMenuBarWindow(from windows: [WindowInfo], for display: CGDirectDisplayID) throws -> WindowInfo {
        guard let window = windows.first(where: Predicates.menuBarWindow(for: display)) else {
            throw WindowListError.noMatchingWindow
        }
        return window
    }

    /// Returns the menu bar window for the given display.
    static func getMenuBarWindow(for display: CGDirectDisplayID) throws -> WindowInfo {
        try getMenuBarWindow(from: getOnScreenWindows(excludeDesktopWindows: true), for: display)
    }
}

// MARK: WindowInfo: Equatable
extension WindowInfo: Equatable {
    static func == (lhs: WindowInfo, rhs: WindowInfo) -> Bool {
        lhs.windowID == rhs.windowID &&
        NSStringFromRect(lhs.frame) == NSStringFromRect(rhs.frame) &&
        lhs.title == rhs.title &&
        lhs.layer == rhs.layer &&
        lhs.alpha == rhs.alpha &&
        lhs.ownerPID == rhs.ownerPID &&
        lhs.ownerName == rhs.ownerName &&
        lhs.sharingState == rhs.sharingState &&
        lhs.backingStoreType == rhs.backingStoreType &&
        lhs.memoryUsage == rhs.memoryUsage &&
        lhs.isOnScreen == rhs.isOnScreen &&
        lhs.isBackedByVideoMemory == rhs.isBackedByVideoMemory
    }
}

// MARK: WindowInfo: Hashable
extension WindowInfo: Hashable {
    func hash(into hasher: inout Hasher) {
        hasher.combine(windowID)
        hasher.combine(NSStringFromRect(frame))
        hasher.combine(title)
        hasher.combine(layer)
        hasher.combine(alpha)
        hasher.combine(ownerPID)
        hasher.combine(ownerName)
        hasher.combine(sharingState)
        hasher.combine(backingStoreType)
        hasher.combine(memoryUsage)
        hasher.combine(isOnScreen)
        hasher.combine(isBackedByVideoMemory)
    }
}
