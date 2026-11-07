//
//  ActiveMenuBarDisplayResolver.swift
//  Shared
//

import CoreGraphics

/// Picks the display whose menu bar is active.
enum ActiveMenuBarDisplayResolver {
    struct Display: Equatable {
        let id: UInt32
        /// The display's bounds in global CoreGraphics coordinates (y down).
        let frame: CGRect
    }

    /// - Parameters:
    ///   - systemID: What the system reports as the active menu bar display
    ///     (it is `nil` on some macOS 26 releases).
    ///   - displays: The active displays.
    ///   - pointer: The pointer in global CoreGraphics coordinates.
    ///   - mainID: `CGMainDisplayID()`.
    static func resolve(systemID: UInt32?, displays: [Display], pointer: CGPoint?, mainID: UInt32) -> UInt32 {
        if let systemID, displays.contains(where: { $0.id == systemID }) {
            return systemID
        }
        if let pointer {
            // Strictly inside first: a point on a shared edge belongs to one display.
            if let display = displays.first(where: { $0.frame.contains(pointer) }) {
                return display.id
            }
            if let display = displays.first(where: { display in
                pointer.x >= display.frame.minX && pointer.x <= display.frame.maxX &&
                pointer.y >= display.frame.minY && pointer.y <= display.frame.maxY
            }) {
                return display.id
            }
        }
        return mainID
    }
}
