//
//  NSScreen+hasNotch.swift
//  Ice
//

import Cocoa

extension NSScreen {
    /// A Boolean value that indicates whether the screen has a notch.
    var hasNotch: Bool {
        safeAreaInsets.top != 0
    }
}
