//
//  MouseCursor.swift
//  Ice
//

import CoreGraphics
import OSLog

/// A namespace for mouse cursor operations.
enum MouseCursor {
    /// Hides the mouse cursor and increments the hide cursor count.
    static func hide() {
        let result = CGDisplayHideCursor(CGMainDisplayID())
        if result != .success {
            Logger.mouseCursor.error("CGDisplayHideCursor failed with error \(result.logString)")
        }
    }

    /// Decrements the hide cursor count and shows the mouse cursor if the count is `0`.
    static func show() {
        let result = CGDisplayShowCursor(CGMainDisplayID())
        if result != .success {
            Logger.mouseCursor.error("CGDisplayShowCursor failed with error \(result.logString)")
        }
    }

    /// Moves the mouse cursor to the given point without generating events.
    ///
    /// - Parameter point: The point to move the cursor to in global display coordinates.
    static func warp(to point: CGPoint) {
        let result = CGWarpMouseCursorPosition(point)
        if result != .success {
            Logger.mouseCursor.error("CGWarpMouseCursorPosition failed with error \(result.logString)")
        }
    }

    /// Returns the location of the mouse pointer.
    ///
    /// If `flipped` is `true`, the coordinate system of the returned location
    /// is relative to the top left corner of the screen, and is compatible with
    /// the coordinate system used by the `CoreGraphics` framework. Otherwise,
    /// the coordinate system of the returned location is relative to the bottom
    /// left corner of the screen, and is compatible with coordinate system used
    /// by the `AppKit` framework.
    static func location(flipped: Bool) -> CGPoint? {
        CGEvent(source: nil).map { event in
            if flipped {
                event.location
            } else {
                event.unflippedLocation
            }
        }
    }
}

// MARK: - Logger

private extension Logger {
    static let mouseCursor = Logger(category: "MouseCursor")
}
