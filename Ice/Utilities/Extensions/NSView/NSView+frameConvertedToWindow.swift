//
//  NSView+frameConvertedToWindow.swift
//  Ice
//

import Cocoa

extension NSView {
    var frameConvertedToWindow: NSRect {
        superview?.convert(frame, to: nil) ?? frame
    }
}
