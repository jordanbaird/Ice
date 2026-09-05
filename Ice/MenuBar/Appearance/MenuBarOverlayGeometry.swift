//
//  MenuBarOverlayGeometry.swift
//  Ice
//

import CoreGraphics

enum MenuBarOverlayGeometry {
    /// AppKit screen coordinates; never create an off-screen or invalid panel.
    static func frame(screen: CGRect, menuBarHeight: CGFloat, inset: CGFloat) -> CGRect? {
        guard [screen.minX, screen.minY, screen.width, screen.height, menuBarHeight, inset].allSatisfy(\.isFinite),
              screen.width > 0, screen.height > 0, menuBarHeight > 0, inset >= 0 else { return nil }
        let height = menuBarHeight + inset
        guard height <= screen.height else { return nil }
        return CGRect(x: screen.minX, y: screen.maxY - height, width: screen.width, height: height)
    }
}
