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
    ///
    /// That is not the only shape a folded item takes. Measured on macOS 27.2, 2026-11-04:
    /// a folded item was listed in MenuBarAgent's own account of the bar at the frame it
    /// would have had, straight across the notch, and its application published no item at
    /// all — Accessibility had no frame of it to test. So this recognises one case of two,
    /// and the notch rule in ``ItemDrawing27`` catches the other.
    static func isInOverflow(itemFrame: CGRect, chevronFrame: CGRect?) -> Bool {
        guard let chevronFrame else {
            return false
        }
        return itemFrame.maxX > chevronFrame.minX && itemFrame.minX < chevronFrame.maxX
    }
}
