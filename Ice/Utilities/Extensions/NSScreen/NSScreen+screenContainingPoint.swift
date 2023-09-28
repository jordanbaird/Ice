//
//  NSScreen+screenContainingPoint.swift
//  Ice
//

import Cocoa

extension NSScreen {
    /// Returns the screen whose frame contains the given point.
    static func screen(containing point: CGPoint) -> NSScreen? {
        screens.first { $0.frame.contains(point) }
    }

    /// Returns the screen whose frame intersects the largest portion
    /// of the given rectangle.
    static func screenWithLargestPortion(of rect: CGRect) -> NSScreen? {
        func intersectionArea(for screen: NSScreen) -> CGFloat {
            let intersection = screen.frame.intersection(rect)
            return intersection.width * intersection.height
        }
        return screens.max {
            intersectionArea(for: $0) < intersectionArea(for: $1)
        }
    }
}
