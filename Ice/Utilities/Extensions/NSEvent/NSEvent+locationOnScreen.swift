//
//  NSEvent+locationOnScreen.swift
//  Ice
//

import Cocoa

extension NSEvent {
    /// The event location in screen coordinates.
    var locationOnScreen: CGPoint {
        // if the event has a window, convert to screen coordinates;
        // otherwise, locationInWindow returns the location on screen
        window?.convertPoint(toScreen: locationInWindow) ?? locationInWindow
    }
}
