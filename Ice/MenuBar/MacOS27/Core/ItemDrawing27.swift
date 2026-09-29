//
//  ItemDrawing27.swift
//  Ice
//

import CoreGraphics

/// Decides whether an item reported through Accessibility is drawn on the active menu bar.
///
/// Accessibility keeps a concealed application's items at the frames where they were last
/// drawn, which can be on the other display (measured on macOS 27.0). Such items still
/// belong in Ice's sections, so they are kept but not treated as drawn.
enum ItemDrawing27 {
    static func isDrawn(itemFrame: CGRect, activeDisplayBounds: CGRect?, chevronFrame: CGRect?) -> Bool {
        if let activeDisplayBounds, !activeDisplayBounds.intersects(itemFrame) {
            return false
        }
        return !OverflowDetection27.isInOverflow(itemFrame: itemFrame, chevronFrame: chevronFrame)
    }
}
