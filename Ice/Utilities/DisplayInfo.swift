//
//  DisplayInfo.swift
//  Ice
//

import Cocoa

struct DisplayInfo {
    let displayID: CGDirectDisplayID
    let frame: CGRect
    let scaleFactor: CGFloat
    let refreshRate: CGRefreshRate
    let colorSpace: CGColorSpace

    init?(displayID: CGDirectDisplayID) {
        guard let mode = CGDisplayCopyDisplayMode(displayID) else {
            return nil
        }
        self.displayID = displayID
        self.frame = CGDisplayBounds(displayID)
        self.scaleFactor = CGFloat(mode.pixelWidth) / CGFloat(mode.width)
        self.refreshRate = mode.refreshRate
        self.colorSpace = CGDisplayCopyColorSpace(displayID)
    }

    init?(nsScreen: NSScreen) {
        self.init(displayID: nsScreen.displayID)
    }

    func getNSScreen() -> NSScreen? {
        NSScreen.screens.first { $0.displayID == displayID }
    }
}

extension DisplayInfo {
    static var main: DisplayInfo? {
        DisplayInfo(displayID: CGMainDisplayID())
    }
}
