//
//  NSEvent+flippedMouseLocation.swift
//  Ice
//

import Cocoa

extension NSEvent {
    /// Returns the current mouse location, flipped along
    /// the Y axis of the screen containing the mouse.
    static var flippedMouseLocation: CGPoint? {
        let loc = mouseLocation
        guard let screen = NSScreen.screens.first(where: { $0.frame.contains(loc) }) else {
            return nil
        }
        return CGPoint(x: loc.x, y: screen.frame.maxY - loc.y)
    }
}
