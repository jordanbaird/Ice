//
//  NSScreen+displayID.swift
//  Ice
//

import Cocoa

extension NSScreen {
    /// The display identifier of the screen.
    var displayID: CGDirectDisplayID {
        // deviceDescription is guaranteed to always have an NSScreenNumber key, so a force unwrap here is okay
        let screenNumber = deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")]! // swiftlint:disable:this force_unwrapping
        return screenNumber as! CGDirectDisplayID // swiftlint:disable:this force_cast
    }
}
