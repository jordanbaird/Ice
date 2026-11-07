//
//  NotchOverflowResolver.swift
//  Ice
//

import CoreGraphics

/// Resolves menu bar items that are present in the visible section but cannot
/// be drawn in the safe area to the right of a display notch.
enum NotchOverflowResolver {
    /// Returns the indices of items obscured by the notch.
    ///
    /// - Parameters:
    ///   - itemBounds: Item bounds in global CoreGraphics coordinates (y down).
    ///   - screenBounds: The target display's bounds in the same coordinates.
    ///   - rightSafeArea: The menu bar area right of the notch (AppKit
    ///     coordinates; only its x range is used).
    ///   - menuBarHeight: The height of the target display's menu bar. Items
    ///     must intersect that strip: displays stacked vertically share the
    ///     same x range, so x alone can't tell their items apart.
    static func obscuredIndices(
        itemBounds: [CGRect?],
        excluding excludedIndices: Set<Int>,
        screenBounds: CGRect,
        rightSafeArea: CGRect?,
        menuBarHeight: CGFloat
    ) -> [Int] {
        guard let rightSafeArea else {
            return []
        }
        let menuBarStrip = CGRect(
            x: screenBounds.minX,
            y: screenBounds.minY,
            width: screenBounds.width,
            height: menuBarHeight
        )

        return itemBounds.indices.filter { index in
            guard
                !excludedIndices.contains(index),
                let bounds = itemBounds[index]
            else {
                return false
            }

            return bounds.width > 0 &&
            bounds.minY < menuBarStrip.maxY &&
            bounds.maxY > menuBarStrip.minY &&
            bounds.maxX > screenBounds.minX &&
            bounds.minX < screenBounds.maxX &&
            bounds.minX < rightSafeArea.minX
        }
    }
}
