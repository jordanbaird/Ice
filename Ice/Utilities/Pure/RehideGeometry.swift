//
//  RehideGeometry.swift
//  Ice
//

import CoreGraphics

/// Geometry for the timed rehide check.
enum RehideGeometry {
    /// Returns whether the pointer is outside the menu bar of the given screen,
    /// so the section may rehide.
    ///
    /// All values are in global AppKit coordinates. Judging against the target
    /// screen (not `NSScreen.main`, the keyboard-focus screen) matters with
    /// several displays: with a monitor above the notebook, the two screens'
    /// y ranges don't overlap.
    static func isPointerOutsideMenuBar(pointer: CGPoint, screenFrame: CGRect, visibleFrame: CGRect) -> Bool {
        let isInsideMenuBar = pointer.x >= screenFrame.minX && pointer.x <= screenFrame.maxX &&
            pointer.y >= visibleFrame.maxY && pointer.y <= screenFrame.maxY
        return !isInsideMenuBar
    }
}
