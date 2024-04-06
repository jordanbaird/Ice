//
//  WindowInfo.swift
//  Ice
//

import Cocoa

/// Information for a window.
struct WindowInfo {
    let windowID: CGWindowID
    let frame: CGRect
    let title: String?
    let windowLayer: Int
    let owningApplication: NSRunningApplication?
    let isOnScreen: Bool

    init?(info: CFDictionary) {
        guard
            let info = info as? [CFString: CFTypeRef],
            let windowID = info[kCGWindowNumber] as? CGWindowID,
            let frameRaw = info[kCGWindowBounds],
            CFGetTypeID(frameRaw) == CFDictionaryGetTypeID(),
            let frame = CGRect(dictionaryRepresentation: frameRaw as! CFDictionary), // swiftlint:disable:this force_cast
            let windowLayer = info[kCGWindowLayer] as? Int,
            let ownerPID = info[kCGWindowOwnerPID] as? Int
        else {
            return nil
        }
        self.windowID = windowID
        self.frame = frame
        self.title = info[kCGWindowName] as? String
        self.windowLayer = windowLayer
        self.owningApplication = NSRunningApplication(processIdentifier: pid_t(ownerPID))
        self.isOnScreen = info[kCGWindowIsOnscreen] as? Bool ?? false
    }
}

extension WindowInfo {
    /// An error that can be thrown during window list operations.
    enum WindowListError: Error {
        /// Indicates an invalid connection to the window server.
        case invalidConnection
    }

    /// Returns an array of the current windows.
    static func getCurrent(option: CGWindowListOption, relativeTo window: WindowInfo? = nil) throws -> [WindowInfo] {
        guard let list = CGWindowListCopyWindowInfo(option, window?.windowID ?? kCGNullWindowID) as? [CFDictionary] else {
            throw WindowListError.invalidConnection
        }
        return list.compactMap { info in
            WindowInfo(info: info)
        }
    }

    /// Asynchronously returns an array of the current windows.
    static func current(option: CGWindowListOption, relativeTo window: WindowInfo? = nil) async throws -> [WindowInfo] {
        let task = Task {
            try getCurrent(option: option, relativeTo: window)
        }
        return try await task.value
    }
}

extension WindowInfo {
    // MARK: Wallpaper Window

    /// A predicate that returns the wallpaper window for the given display.
    private static func wallpaperWindowPredicate(for display: DisplayInfo) -> (WindowInfo) -> Bool {
        return { window in
            // wallpaper window belongs to the Dock process
            window.owningApplication?.bundleIdentifier == "com.apple.dock" &&
            window.title?.hasPrefix("Wallpaper-") == true &&
            display.frame.contains(window.frame)
        }
    }

    /// Returns the wallpaper window in the given windows for the given display.
    static func getWallpaperWindow(from windows: [WindowInfo], for display: DisplayInfo) -> WindowInfo? {
        windows.first(where: wallpaperWindowPredicate(for: display))
    }

    /// Returns the wallpaper window for the given display.
    static func getWallpaperWindow(for display: DisplayInfo) throws -> WindowInfo? {
        try getWallpaperWindow(from: getCurrent(option: .optionOnScreenOnly), for: display)
    }

    /// Asynchronously returns the wallpaper window for the given display.
    static func wallpaperWindow(for display: DisplayInfo) async throws -> WindowInfo? {
        try await getWallpaperWindow(from: current(option: .optionOnScreenOnly), for: display)
    }

    // MARK: Menu Bar Window

    /// A predicate that returns the menu bar window for the given display.
    private static func menuBarWindowPredicate(for display: DisplayInfo) -> (WindowInfo) -> Bool {
        return { window in
            // menu bar window belongs to the WindowServer process (owningApplication should be nil)
            window.owningApplication == nil &&
            window.title == "Menubar" &&
            window.windowLayer == kCGMainMenuWindowLevel &&
            display.frame.contains(window.frame)
        }
    }

    /// Returns the menu bar window for the given display.
    static func getMenuBarWindow(from windows: [WindowInfo], for display: DisplayInfo) -> WindowInfo? {
        windows.first(where: menuBarWindowPredicate(for: display))
    }

    /// Returns the menu bar window for the given display.
    static func getMenuBarWindow(for display: DisplayInfo) throws -> WindowInfo? {
        try getMenuBarWindow(from: getCurrent(option: .optionOnScreenOnly), for: display)
    }

    /// Asynchronously returns the menu bar window for the given display.
    static func menuBarWindow(for display: DisplayInfo) async throws -> WindowInfo? {
        try await getMenuBarWindow(from: current(option: .optionOnScreenOnly), for: display)
    }
}
