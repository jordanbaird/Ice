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

    /// Gets an array of the current windows.
    static func getCurrent(option: CGWindowListOption, relativeTo windowID: CGWindowID? = nil) -> [WindowInfo] {
        guard let list = CGWindowListCopyWindowInfo(option, windowID ?? kCGNullWindowID) as? [CFDictionary] else {
            return []
        }
        return list.compactMap { info in
            WindowInfo(info: info)
        }
    }

    /// Returns the wallpaper window for the given display.
    static func wallpaperWindow(for display: DisplayInfo) -> WindowInfo? {
        getCurrent(option: .optionOnScreenOnly).first { window in
            // wallpaper window belongs to the Dock process
            window.owningApplication?.bundleIdentifier == "com.apple.dock" &&
            window.title?.hasPrefix("Wallpaper-") == true &&
            display.frame.contains(window.frame)
        }
    }

    /// Returns the menu bar window for the given display.
    static func menuBarWindow(for display: DisplayInfo) -> WindowInfo? {
        getCurrent(option: .optionOnScreenOnly).first { window in
            // menu bar window belongs to the WindowServer process
            // (owningApplication should be nil)
            window.owningApplication == nil &&
            window.title == "Menubar" &&
            window.windowLayer == kCGMainMenuWindowLevel &&
            display.frame.contains(window.frame)
        }
    }
}
