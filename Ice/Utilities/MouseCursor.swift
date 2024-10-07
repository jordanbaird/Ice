//
//  MouseCursor.swift
//  Ice
//

import CoreGraphics

/// A namespace for mouse cursor operations.
enum MouseCursor {
    /// A coordinate space for mouse cursor operations.
    enum CoordinateSpace {
        /// The coordinate space used by the `AppKit` framework.
        ///
        /// The origin of this coordinate space is at the bottom left corner of the screen.
        case appKit

        /// The coordinate space used by the `CoreGraphics` framework.
        ///
        /// The origin of this coordinate space is at the top left corner of the screen.
        case coreGraphics
    }

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
    /// - Parameter coordinateSpace: The coordinate space of the returned location. See
    ///   the constants defined in ``MouseCursor/CoordinateSpace`` for more information.
    static func location(in coordinateSpace: CoordinateSpace) -> CGPoint? {
        CGEvent(source: nil).map { event in
            switch coordinateSpace {
            case .appKit:
                event.unflippedLocation
            case .coreGraphics:
                event.location
            }
        }
    }
}

// MARK: - Logger
private extension Logger {
    static let mouseCursor = Logger(category: "MouseCursor")
}
