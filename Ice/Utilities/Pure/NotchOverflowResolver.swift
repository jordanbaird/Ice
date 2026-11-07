//
//  NotchOverflowResolver.swift
//  Ice
//

import CoreGraphics

/// Resolves menu bar items that are present in the visible section but cannot
/// be drawn in the safe area to the right of a display notch.
enum NotchOverflowResolver {
    /// Returns the indices of items obscured by the notch.
    static func obscuredIndices(
        itemBounds: [CGRect?],
        excluding excludedIndices: Set<Int>,
        screenBounds: CGRect,
        rightSafeArea: CGRect?
    ) -> [Int] {
        guard let rightSafeArea else {
            return []
        }

        return itemBounds.indices.filter { index in
            guard
                !excludedIndices.contains(index),
                let bounds = itemBounds[index]
            else {
                return false
            }

            return bounds.width > 0 &&
            bounds.maxX > screenBounds.minX &&
            bounds.minX < screenBounds.maxX &&
            bounds.minX < rightSafeArea.minX
        }
    }
}
