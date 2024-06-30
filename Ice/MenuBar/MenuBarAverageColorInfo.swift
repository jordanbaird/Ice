//
//  MenuBarAverageColorInfo.swift
//  Ice
//

import CoreGraphics

/// Information for the menu bar's average color.
struct MenuBarAverageColorInfo: Hashable {
    enum Source: Hashable {
        case menuBarWindow
        case desktopWallpaper
    }

    var color: CGColor
    var source: Source
}
