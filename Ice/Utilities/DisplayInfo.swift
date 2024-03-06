//
//  DisplayInfo.swift
//  Ice
//

import CoreGraphics

struct DisplayInfo {
    let displayID: CGDirectDisplayID
    let frame: CGRect
    let scaleFactor: CGFloat

    init?(displayID: CGDirectDisplayID) {
        guard let mode = CGDisplayCopyDisplayMode(displayID) else {
            return nil
        }
        self.displayID = displayID
        self.frame = CGRect(x: 0, y: 0, width: mode.width, height: mode.height)
        self.scaleFactor = CGFloat(mode.pixelWidth) / CGFloat(mode.width)
    }
}

extension DisplayInfo {
    static var main: DisplayInfo? {
        DisplayInfo(displayID: CGMainDisplayID())
    }
}
