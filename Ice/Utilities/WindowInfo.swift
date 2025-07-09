//
//  WindowInfo.swift
//  Ice
//

import Cocoa

/// Information for a window.
struct WindowInfo {
    /// The window's identifier.
    let windowID: CGWindowID

    /// The identifier of the process that owns the window.
    let ownerPID: pid_t

    /// The window's bounds, specified in screen coordinates.
    let bounds: CGRect

    /// The window's layer number.
    let layer: Int

    /// The window's title.
    let title: String?

    /// The name of the process that owns the window.
    ///
    /// This may have a value when ``owningApplication`` does not have
    /// a localized name.
    let ownerName: String?

    /// A Boolean value that indicates whether the window is on screen.
    let isOnScreen: Bool

    /// The application that owns the window.
    var owningApplication: NSRunningApplication? {
        NSRunningApplication(processIdentifier: ownerPID)
    }

    /// A Boolean value that indicates whether the window belongs to the
    /// window server.
    var isWindowServerWindow: Bool {
        ownerName == "Window Server"
    }

    /// Creates a window with the given dictionary.
    private init?(dictionary: CFDictionary) {
        guard
            let info = dictionary as? [CFString: Any],
            let windowID = info[kCGWindowNumber] as? CGWindowID,
            let ownerPID = info[kCGWindowOwnerPID] as? pid_t,
            let boundsDict = info[kCGWindowBounds] as? NSDictionary,
            let bounds = CGRect(dictionaryRepresentation: boundsDict),
            let layer = info[kCGWindowLayer] as? Int
        else {
            return nil
        }
        self.windowID = windowID
        self.ownerPID = ownerPID
        self.bounds = bounds
        self.layer = layer
        self.title = info[kCGWindowName] as? String
        self.ownerName = info[kCGWindowOwnerName] as? String
        self.isOnScreen = info[kCGWindowIsOnscreen] as? Bool ?? false
    }

    /// Creates a window with the given window identifier.
    init?(windowID: CGWindowID) {
        guard
            let array = Bridging.createCGWindowArray(with: [windowID]),
            let list = CGWindowListCreateDescriptionFromArray(array) as? [CFDictionary],
            let dictionary = list.first
        else {
            return nil
        }
        self.init(dictionary: dictionary)
    }
}

// MARK: - WindowList Operations

// MARK: All Windows
extension WindowInfo {
    /// Returns a list of windows using the given options.
    ///
    /// - Parameter option: Options that filter the returned list.
    ///   Pass an empty option set to return all available windows.
    static func getWindows(option: Bridging.WindowListOption = []) -> [WindowInfo] {
        Bridging.getWindowList(option: option).compactMap { WindowInfo(windowID: $0) }
    }
}

// MARK: Wallpaper Window
extension WindowInfo {
    /// Returns the wallpaper window in the given windows for the given display.
    static func getWallpaperWindow(from windows: [WindowInfo], for display: CGDirectDisplayID) -> WindowInfo? {
        windows.first(where: Predicates.wallpaperWindow(for: display))
    }

    /// Returns the wallpaper window for the given display.
    static func getWallpaperWindow(for display: CGDirectDisplayID) -> WindowInfo? {
        getWallpaperWindow(from: getWindows(option: .onScreen), for: display)
    }
}

// MARK: Menu Bar Window
extension WindowInfo {
    /// Returns the menu bar window for the given display.
    static func getMenuBarWindow(from windows: [WindowInfo], for display: CGDirectDisplayID) -> WindowInfo? {
        windows.first(where: Predicates.menuBarWindow(for: display))
    }

    /// Returns the menu bar window for the given display.
    static func getMenuBarWindow(for display: CGDirectDisplayID) -> WindowInfo? {
        getMenuBarWindow(from: getWindows(option: .onScreen), for: display)
    }
}

// MARK: WindowInfo: Equatable
extension WindowInfo: Equatable {
    static func == (lhs: WindowInfo, rhs: WindowInfo) -> Bool {
        lhs.windowID == rhs.windowID &&
        lhs.ownerPID == rhs.ownerPID &&
        NSStringFromRect(lhs.bounds) == NSStringFromRect(rhs.bounds) &&
        lhs.layer == rhs.layer &&
        lhs.title == rhs.title &&
        lhs.ownerName == rhs.ownerName &&
        lhs.isOnScreen == rhs.isOnScreen
    }
}

// MARK: WindowInfo: Hashable
extension WindowInfo: Hashable {
    func hash(into hasher: inout Hasher) {
        hasher.combine(windowID)
        hasher.combine(ownerPID)
        hasher.combine(NSStringFromRect(bounds))
        hasher.combine(layer)
        hasher.combine(title)
        hasher.combine(ownerName)
        hasher.combine(isOnScreen)
    }
}
