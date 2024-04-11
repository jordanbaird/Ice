//
//  WindowInfo.swift
//  Ice
//

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
    let windowLayer: Int

    /// The application that owns the window.
    let owningApplication: NSRunningApplication?

    /// A Boolean value that indicates whether the window is on screen.
    let isOnScreen: Bool

    private init?(info: CFDictionary) {
        guard
            let info = info as? [CFString: CFTypeRef],
            let windowID = info[kCGWindowNumber] as? CGWindowID,
            let boundsDict = info[kCGWindowBounds] as? NSDictionary,
            let frame = CGRect(dictionaryRepresentation: boundsDict),
            let windowLayer = info[kCGWindowLayer] as? Int,
            let ownerPID = info[kCGWindowOwnerPID] as? pid_t
        else {
            return nil
        }
        self.windowID = windowID
        self.frame = frame
        self.title = info[kCGWindowName] as? String
        self.windowLayer = windowLayer
        self.owningApplication = NSRunningApplication(processIdentifier: ownerPID)
        self.isOnScreen = info[kCGWindowIsOnscreen] as? Bool ?? false
    }
}

// MARK: - WindowList Operations

extension WindowInfo {

    // MARK: WindowListError

    /// An error that can be thrown during window list operations.
    enum WindowListError: Error {
        /// Indicates an invalid connection to the window server.
        case invalidConnection
        /// Indicates that the desired window is not present in the list.
        case noMatchingWindow
    }
}

// MARK: Private
extension WindowInfo {
    private enum OnScreenOption {
        case above(window: WindowInfo, include: Bool)
        case below(window: WindowInfo, include: Bool)
        case onScreenOnly
    }

    private static func copyWindowList(option: CGWindowListOption, windowID: CGWindowID?) throws -> [CFDictionary] {
        guard let list = CGWindowListCopyWindowInfo(option, windowID ?? kCGNullWindowID) as? [CFDictionary] else {
            throw WindowListError.invalidConnection
        }
        return list
    }

    private static func getCurrent(option: CGWindowListOption, relativeTo window: WindowInfo?) throws -> [WindowInfo] {
        let list = try copyWindowList(option: option, windowID: window?.windowID)
        return list.compactMap { info in
            WindowInfo(info: info)
        }
    }

    private static func getOnScreenWindows(option: OnScreenOption, excludeDesktopWindows: Bool) throws -> [WindowInfo] {
        var listOption: CGWindowListOption = []
        var referenceWindow: WindowInfo?
        switch option {
        case .above(let window, let include):
            listOption.insert(.optionOnScreenAboveWindow)
            if include {
                listOption.insert(.optionIncludingWindow)
            }
            referenceWindow = window
        case .below(let window, let include):
            listOption.insert(.optionOnScreenBelowWindow)
            if include {
                listOption.insert(.optionIncludingWindow)
            }
            referenceWindow = window
        case .onScreenOnly:
            listOption.insert(.optionOnScreenOnly)
        }
        if excludeDesktopWindows {
            listOption.insert(.excludeDesktopElements)
        }
        return try getCurrent(option: listOption, relativeTo: referenceWindow)
    }

    private static func current(option: CGWindowListOption, relativeTo window: WindowInfo?) async throws -> [WindowInfo] {
        let task = Task.detached {
            let list = try copyWindowList(option: option, windowID: window?.windowID)

            try Task.checkCancellation()
            await Task.yield()

            var windows = [WindowInfo]()
            for info in list {
                try Task.checkCancellation()
                await Task.yield()
                if let window = WindowInfo(info: info) {
                    windows.append(window)
                }
            }

            return windows
        }

        return try await withTaskCancellationHandler {
            try await task.value
        } onCancel: {
            task.cancel()
        }
    }

    private static func onScreenWindows(option: OnScreenOption, excludeDesktopWindows: Bool) async throws -> [WindowInfo] {
        var listOption: CGWindowListOption = []
        var referenceWindow: WindowInfo?
        switch option {
        case .above(let window, let include):
            listOption.insert(.optionOnScreenAboveWindow)
            if include {
                listOption.insert(.optionIncludingWindow)
            }
            referenceWindow = window
        case .below(let window, let include):
            listOption.insert(.optionOnScreenBelowWindow)
            if include {
                listOption.insert(.optionIncludingWindow)
            }
            referenceWindow = window
        case .onScreenOnly:
            listOption.insert(.optionOnScreenOnly)
        }
        if excludeDesktopWindows {
            listOption.insert(.excludeDesktopElements)
        }
        return try await current(option: listOption, relativeTo: referenceWindow)
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
        return try getCurrent(option: option, relativeTo: nil)
    }

    /// Asynchronously returns the current windows.
    ///
    /// - Parameter excludeDesktopWindows: A Boolean value that indicates whether
    ///   to exclude desktop owned windows, such as the wallpaper and desktop icons.
    static func allWindows(excludeDesktopWindows: Bool = false) async throws -> [WindowInfo] {
        var option = CGWindowListOption.optionAll
        if excludeDesktopWindows {
            option.insert(.excludeDesktopElements)
        }
        return try await current(option: option, relativeTo: nil)
    }
}

// MARK: On Screen Windows
extension WindowInfo {

    // MARK: Sync

    /// Returns the on screen windows.
    ///
    /// - Parameter excludeDesktopWindows: A Boolean value that indicates whether
    ///   to exclude desktop owned windows, such as the wallpaper and desktop icons.
    static func getOnScreenWindows(excludeDesktopWindows: Bool = false) throws -> [WindowInfo] {
        try getOnScreenWindows(
            option: .onScreenOnly,
            excludeDesktopWindows: excludeDesktopWindows
        )
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
        try getOnScreenWindows(
            option: .above(window: window, include: includeWindow),
            excludeDesktopWindows: excludeDesktopWindows
        )
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
        try getOnScreenWindows(
            option: .below(window: window, include: includeWindow),
            excludeDesktopWindows: excludeDesktopWindows
        )
    }

    // MARK: Async

    /// Asynchronously returns the on screen windows.
    ///
    /// - Parameter excludeDesktopWindows: A Boolean value that indicates whether
    ///   to exclude desktop owned windows, such as the wallpaper and desktop icons.
    static func onScreenWindows(excludeDesktopWindows: Bool = false) async throws -> [WindowInfo] {
        try await onScreenWindows(
            option: .onScreenOnly,
            excludeDesktopWindows: excludeDesktopWindows
        )
    }

    /// Asynchronously returns the on screen windows above the given window.
    ///
    /// - Parameters:
    ///   - window: The window to use as a reference point when determining which
    ///     windows to return.
    ///   - includeWindow: A Boolean value that indicates whether to include the
    ///     window in the result.
    ///   - excludeDesktopWindows: A Boolean value that indicates whether to exclude
    ///     desktop owned windows, such as the wallpaper and desktop icons.
    static func onScreenWindows(
        above window: WindowInfo,
        includeWindow: Bool = false,
        excludeDesktopWindows: Bool = false
    ) async throws -> [WindowInfo] {
        try await onScreenWindows(
            option: .above(window: window, include: includeWindow),
            excludeDesktopWindows: excludeDesktopWindows
        )
    }

    /// Asynchronously returns the on screen windows below the given window.
    ///
    /// - Parameters:
    ///   - window: The window to use as a reference point when determining which
    ///     windows to return.
    ///   - includeWindow: A Boolean value that indicates whether to include the
    ///     window in the result.
    ///   - excludeDesktopWindows: A Boolean value that indicates whether to exclude
    ///     desktop owned windows, such as the wallpaper and desktop icons.
    static func onScreenWindows(
        below window: WindowInfo,
        includeWindow: Bool = false,
        excludeDesktopWindows: Bool = false
    ) async throws -> [WindowInfo] {
        try await onScreenWindows(
            option: .below(window: window, include: includeWindow),
            excludeDesktopWindows: excludeDesktopWindows
        )
    }
}

// MARK: Single Windows
extension WindowInfo {

    // MARK: - Wallpaper Window

    /// A predicate that returns the wallpaper window for the given display.
    private static func wallpaperWindowPredicate(for display: DisplayInfo) -> (WindowInfo) -> Bool {
        return { window in
            // wallpaper window belongs to the Dock process
            window.owningApplication?.bundleIdentifier == "com.apple.dock" &&
            window.title?.hasPrefix("Wallpaper-") == true &&
            display.frame.contains(window.frame)
        }
    }

    // MARK: Sync

    /// Returns the wallpaper window in the given windows for the given display.
    static func getWallpaperWindow(from windows: [WindowInfo], for display: DisplayInfo) throws -> WindowInfo {
        guard let window = windows.first(where: wallpaperWindowPredicate(for: display)) else {
            throw WindowListError.noMatchingWindow
        }
        return window
    }

    /// Returns the wallpaper window for the given display.
    static func getWallpaperWindow(for display: DisplayInfo) throws -> WindowInfo {
        try getWallpaperWindow(from: getOnScreenWindows(), for: display)
    }

    // MARK: Async

    /// Asynchronously returns the wallpaper window in the given windows for the given display.
    static func wallpaperWindow(from windows: [WindowInfo], for display: DisplayInfo) async throws -> WindowInfo {
        let predicate = wallpaperWindowPredicate(for: display)
        for window in windows {
            try Task.checkCancellation()
            await Task.yield()
            if predicate(window) {
                return window
            }
        }
        throw WindowListError.noMatchingWindow
    }

    /// Asynchronously returns the wallpaper window for the given display.
    static func wallpaperWindow(for display: DisplayInfo) async throws -> WindowInfo {
        try await wallpaperWindow(from: onScreenWindows(), for: display)
    }

    // MARK: - Menu Bar Window

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

    // MARK: Sync

    /// Returns the menu bar window for the given display.
    static func getMenuBarWindow(from windows: [WindowInfo], for display: DisplayInfo) throws -> WindowInfo {
        guard let window = windows.first(where: menuBarWindowPredicate(for: display)) else {
            throw WindowListError.noMatchingWindow
        }
        return window
    }

    /// Returns the menu bar window for the given display.
    static func getMenuBarWindow(for display: DisplayInfo) throws -> WindowInfo {
        try getMenuBarWindow(from: getOnScreenWindows(excludeDesktopWindows: true), for: display)
    }

    // MARK: Async

    /// Asynchronously returns the menu bar window for the given display.
    static func menuBarWindow(from windows: [WindowInfo], for display: DisplayInfo) async throws -> WindowInfo {
        let predicate = menuBarWindowPredicate(for: display)
        for window in windows {
            try Task.checkCancellation()
            await Task.yield()
            if predicate(window) {
                return window
            }
        }
        throw WindowListError.noMatchingWindow
    }

    /// Asynchronously returns the menu bar window for the given display.
    static func menuBarWindow(for display: DisplayInfo) async throws -> WindowInfo {
        try await menuBarWindow(from: onScreenWindows(excludeDesktopWindows: true), for: display)
    }
}
