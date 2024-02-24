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
}
