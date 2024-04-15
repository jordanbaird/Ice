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

    /// Creates a window with the given dictionary.
    private init?(dictionary: CFDictionary) {
        guard
            let info = dictionary as? [CFString: CFTypeRef],
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
            throw WindowListError.invalidConnection
        }
        return list
    }

    /// Synchronously returns the current window list using the given context.
    private static func getWindowList(context: WindowListContext) throws -> [WindowInfo] {
        let list = try copyWindowListArray(context: context)
        return list.compactMap { WindowInfo(dictionary: $0) }
    }

    /// Asynchronously returns the current window list using the given context.
    private static func windowList(context: WindowListContext) async throws -> [WindowInfo] {
        let task = Task.detached {
            let list = try copyWindowListArray(context: context)

            try Task.checkCancellation()
            await Task.yield()

            var windows = [WindowInfo]()
            for dictionary in list {
                try Task.checkCancellation()
                await Task.yield()
                if let window = WindowInfo(dictionary: dictionary) {
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

    /// Asynchronously returns the current windows.
    ///
    /// - Parameter excludeDesktopWindows: A Boolean value that indicates whether
    ///   to exclude desktop owned windows, such as the wallpaper and desktop icons.
    static func allWindows(excludeDesktopWindows: Bool = false) async throws -> [WindowInfo] {
        var option = CGWindowListOption.optionAll
        if excludeDesktopWindows {
            option.insert(.excludeDesktopElements)
        }
        let context = WindowListContext(windowListOption: option, referenceWindow: nil)
        return try await windowList(context: context)
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

    // MARK: Async

    /// Asynchronously returns the on screen windows.
    ///
    /// - Parameter excludeDesktopWindows: A Boolean value that indicates whether
    ///   to exclude desktop owned windows, such as the wallpaper and desktop icons.
    static func onScreenWindows(excludeDesktopWindows: Bool = false) async throws -> [WindowInfo] {
        let context = WindowListContext(
            onScreenOption: .onScreenOnly,
            excludeDesktopWindows: excludeDesktopWindows
        )
        return try await windowList(context: context)
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
        let context = WindowListContext(
            onScreenOption: .above(window, includeWindow: includeWindow),
            excludeDesktopWindows: excludeDesktopWindows
        )
        return try await windowList(context: context)
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
        let context = WindowListContext(
            onScreenOption: .below(window, includeWindow: includeWindow),
            excludeDesktopWindows: excludeDesktopWindows
        )
        return try await windowList(context: context)
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
            display.bounds.contains(window.frame)
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
            display.bounds.contains(window.frame)
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
