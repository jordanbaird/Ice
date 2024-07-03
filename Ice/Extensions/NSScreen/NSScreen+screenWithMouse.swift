//
//  NSScreen+screenWithMouse.swift
//  Ice
//

import Cocoa

extension NSScreen {
    /// Returns the screen containing the mouse pointer.
    static var screenWithMouse: NSScreen? {
        screens.first { $0.frame.contains(NSEvent.mouseLocation) }
    }
}
