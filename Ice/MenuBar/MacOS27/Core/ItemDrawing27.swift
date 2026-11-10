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
    /// - Parameter notchXRange: The span the active display's notch covers, or `nil` where it
    ///   has none. See `NotchGeometry27`.
    static func isDrawn(
        itemFrame: CGRect,
        activeDisplayBounds: CGRect?,
        notchXRange: ClosedRange<CGFloat>? = nil,
        chevronFrame: CGRect?
    ) -> Bool {
        if let activeDisplayBounds, !activeDisplayBounds.intersects(itemFrame) {
            return false
        }
        // An item the bar has laid out across the notch is drawn on nothing, and a click where
        // it says it is lands on nothing.
        if let notchXRange, itemFrame.minX < notchXRange.upperBound, itemFrame.maxX > notchXRange.lowerBound {
            return false
        }
        return !OverflowDetection27.isInOverflow(itemFrame: itemFrame, chevronFrame: chevronFrame)
    }
}
