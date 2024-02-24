//
//  NSScreen+isMouseInMenuBar.swift
//  Ice
//

import Cocoa

extension NSScreen {
    /// A Boolean value that indicates whether the mouse
    /// is inside the bounds of the screen's menu bar.
    var isMouseInMenuBar: Bool {
        NSEvent.mouseLocation.y > visibleFrame.maxY &&
        NSEvent.mouseLocation.y <= frame.maxY
    }
}
