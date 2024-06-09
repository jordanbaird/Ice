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
            Logger.mouseCursor.error("CGDisplayHideCursor failed with error \(getDescription(for: result))")
        }
    }

    /// Decrements the hide cursor count and shows the mouse cursor if the count is `0`.
    static func show() {
        let result = CGDisplayShowCursor(CGMainDisplayID())
        if result != .success {
            Logger.mouseCursor.error("CGDisplayShowCursor failed with error \(getDescription(for: result))")
        }
    }

    /// Moves the mouse cursor to the given point without generating events.
    ///
    /// - Parameter point: The point to move the cursor to in global display coordinates.
    static func warpPosition(to point: CGPoint) {
        let result = CGWarpMouseCursorPosition(point)
        if result != .success {
            Logger.mouseCursor.error("CGWarpMouseCursorPosition failed with error \(getDescription(for: result))")
        }
    }

    /// Returns a description for the given `CGError`.
    private static func getDescription(for error: CGError) -> String {
        switch error {
        case .success: "\(error.rawValue): success"
        case .failure: "\(error.rawValue): failure"
        case .illegalArgument: "\(error.rawValue): illegalArgument"
        case .invalidConnection: "\(error.rawValue): invalidConnection"
        case .invalidContext: "\(error.rawValue): invalidContext"
        case .cannotComplete: "\(error.rawValue): cannotComplete"
        case .notImplemented: "\(error.rawValue): notImplemented"
        case .rangeCheck: "\(error.rawValue): rangeCheck"
        case .typeCheck: "\(error.rawValue): typeCheck"
        case .invalidOperation: "\(error.rawValue): invalidOperation"
        case .noneAvailable: "\(error.rawValue): noneAvailable"
        @unknown default: "\(error.rawValue): unknown"
        }
    }
}

// MARK: - Logger

private extension Logger {
    static let mouseCursor = Logger(category: "MouseCursor")
}
