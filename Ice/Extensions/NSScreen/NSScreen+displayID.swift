//
//  NSScreen+displayID.swift
//  Ice
//

import Cocoa

extension NSScreen {
    /// The display identifier of the screen.
    var displayID: CGDirectDisplayID {
        // deviceDescription dictionary is guaranteed to always have an "NSScreenNumber"
        // key with a CGDirectDisplayID as its value, so a force unwrap and cast is okay
        // swiftlint:disable:next force_unwrapping
        let screenNumber = deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")]!
        // swiftlint:disable:next force_cast
        return screenNumber as! CGDirectDisplayID
    }
}
