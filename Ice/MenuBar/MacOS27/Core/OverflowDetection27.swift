//
//  OverflowDetection27.swift
//  Ice
//

import CoreGraphics

/// Recognises items folded into the system overflow on macOS 27.
enum OverflowDetection27 {
    /// Measured on macOS 27.0: while the overflow is collapsed, every folded item
    /// reports a frame stacked against the overflow button, overlapping it. While it
    /// is expanded, folded items are drawn and report their real frames.
    static func isInOverflow(itemFrame: CGRect, chevronFrame: CGRect?) -> Bool {
        guard let chevronFrame else {
            return false
        }
        return itemFrame.maxX > chevronFrame.minX && itemFrame.minX < chevronFrame.maxX
    }
}
