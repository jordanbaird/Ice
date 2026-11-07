//
//  NotchBarPolicy.swift
//  Ice
//

/// Decides when hidden items go to the Trincano Bar because of the notch.
enum NotchBarPolicy {
    /// Space kept free at the notch edge, in points.
    static let margin: Double = 8

    /// Returns whether the Trincano Bar must be used instead of expanding
    /// the menu bar inline.
    ///
    /// - Parameters:
    ///   - isEnabled: The user setting.
    ///   - rightSafeAreaWidth: The width of the menu bar area to the right of
    ///     the notch, or `nil` if the screen has no notch.
    ///   - obscuredCount: How many items are already pushed behind the notch.
    ///   - expandedItemWidths: The widths of every item that would be shown
    ///     inline if the section expanded.
    static func shouldUseBar(
        isEnabled: Bool,
        rightSafeAreaWidth: Double?,
        obscuredCount: Int,
        expandedItemWidths: [Double]
    ) -> Bool {
        guard isEnabled, let rightSafeAreaWidth else {
            return false
        }
        if obscuredCount > 0 {
            return true
        }
        return expandedItemWidths.reduce(0, +) > rightSafeAreaWidth - margin
    }
}

/// Decides whether a click toggles the Trincano Bar from the notch.
enum NotchClickPolicy {
    static func shouldToggleBar(isEnabled: Bool, hasNotch: Bool, clickIsInsideNotch: Bool) -> Bool {
        isEnabled && hasNotch && clickIsInsideNotch
    }
}
