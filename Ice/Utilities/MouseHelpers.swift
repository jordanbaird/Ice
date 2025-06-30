//
//  MouseHelpers.swift
//  Ice
//

import CoreGraphics
import OSLog

/// A namespace for mouse cursor operations.
enum MouseCursor {
    /// Returns the location of the mouse cursor in the coordinate space used by
    /// the `AppKit` framework, with the origin at the bottom left of the screen.
    static var locationAppKit: CGPoint? {
        CGEvent(source: nil)?.unflippedLocation
    }

    /// Returns the location of the mouse cursor in the coordinate space used by
    /// the `CoreGraphics` framework, with the origin at the top left of the screen.
    static var locationCoreGraphics: CGPoint? {
        CGEvent(source: nil)?.location
    }

    /// Hides the mouse cursor and increments the hide cursor count.
    static func hide() {
        let result = CGDisplayHideCursor(CGMainDisplayID())
        if result != .success {
            Logger.general.error("CGDisplayHideCursor failed with error \(result.logString, privacy: .public)")
        }
    }

    /// Decrements the hide cursor count and shows the mouse cursor if the count is `0`.
    static func show() {
        let result = CGDisplayShowCursor(CGMainDisplayID())
        if result != .success {
            Logger.general.error("CGDisplayShowCursor failed with error \(result.logString, privacy: .public)")
        }
    }

    /// Moves the mouse cursor to the given point without generating events.
    ///
    /// - Parameter point: The point to move the cursor to in global display coordinates.
    static func warp(to point: CGPoint) {
        let result = CGWarpMouseCursorPosition(point)
        if result != .success {
            Logger.general.error("CGWarpMouseCursorPosition failed with error \(result.logString, privacy: .public)")
        }
    }
}

// MARK: - MouseEvents

/// A namespace for mouse event operations.
enum MouseEvents {
    /// Returns a Boolean value that indicates whether a mouse button
    /// is pressed.
    ///
    /// - Parameter button: The mouse button to check. Pass `nil` to
    ///   check all available mouse buttons (Quartz supports up to 32).
    static func isButtonPressed(_ button: CGMouseButton? = nil) -> Bool {
        let stateID = CGEventSourceStateID.combinedSessionState
        if let button {
            return CGEventSource.buttonState(stateID, button: button)
        }
        for n: UInt32 in 0...31 {
            guard
                let button = CGMouseButton(rawValue: n),
                CGEventSource.buttonState(stateID, button: button)
            else {
                continue
            }
            return true
        }
        return false
    }

    /// Returns a Boolean value that indicates whether the last mouse
    /// movement event occurred within the given duration.
    ///
    /// - Parameter interval: The duration within which the last mouse
    ///   movement event must have occurred in order to return `true`.
    static func lastMovementOccurred(within duration: Duration) -> Bool {
        let stateID = CGEventSourceStateID.combinedSessionState
        let seconds = CGEventSource.secondsSinceLastEventType(stateID, eventType: .mouseMoved)
        return .seconds(seconds) <= duration
    }
}
