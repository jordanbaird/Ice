//
//  NotchGeometry.swift
//  Ice
//

import CoreGraphics

/// The geometry of a display's notch (or pill), derived only from the screen's
/// safe area, so it works for any notch shape and size without constants.
///
/// All rectangles are in global AppKit coordinates, exactly as `NSScreen`
/// reports `auxiliaryTopLeftArea` and `auxiliaryTopRightArea` (they already
/// include the display's origin).
struct NotchGeometry: Equatable {
    /// The area covered by the notch.
    let frame: CGRect

    /// The menu bar area to the left of the notch (application menus).
    let leftSafeArea: CGRect

    /// The menu bar area to the right of the notch (menu bar items).
    let rightSafeArea: CGRect

    /// Returns `nil` for a screen without a usable notch.
    init?(
        screenFrame: CGRect,
        safeAreaTop: CGFloat,
        auxiliaryTopLeftArea: CGRect?,
        auxiliaryTopRightArea: CGRect?
    ) {
        guard
            safeAreaTop > 0,
            let left = auxiliaryTopLeftArea,
            let right = auxiliaryTopRightArea,
            right.minX > left.maxX
        else {
            return nil
        }
        frame = CGRect(
            x: left.maxX,
            y: screenFrame.maxY - safeAreaTop,
            width: right.minX - left.maxX,
            height: safeAreaTop
        )
        leftSafeArea = left
        rightSafeArea = right
    }

    /// Returns whether the point is over the notch. The top edge counts as
    /// inside: the pointer can sit exactly on the screen's top edge.
    func contains(_ point: CGPoint) -> Bool {
        point.x >= frame.minX && point.x < frame.maxX &&
        point.y >= frame.minY && point.y <= frame.maxY
    }
}
