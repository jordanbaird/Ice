//
//  NotchBarSession.swift
//  Ice
//

/// Holds the "use the Trincano Bar because of the notch" decision for one
/// show-to-hide cycle of a section.
///
/// The decision is recomputed from **live** measurements every time the
/// section is about to be shown (a dynamic item can grow or shrink with the
/// same window ID, so a cached width or count would be stale), and is then
/// pinned until the section is hidden, so it can't flip while expanded.
struct NotchBarSession {
    private(set) var isUsingBar = false

    /// Starts a cycle. The measurements are only read here.
    mutating func begin(
        isEnabled: Bool,
        rightSafeAreaWidth: Double?,
        obscuredCount: () -> Int,
        expandedItemWidths: () -> [Double]
    ) -> Bool {
        guard isEnabled, rightSafeAreaWidth != nil else {
            isUsingBar = false
            return false
        }
        isUsingBar = NotchBarPolicy.shouldUseBar(
            isEnabled: isEnabled,
            rightSafeAreaWidth: rightSafeAreaWidth,
            obscuredCount: obscuredCount(),
            expandedItemWidths: expandedItemWidths()
        )
        return isUsingBar
    }

    /// Ends the cycle (the section was hidden).
    mutating func end() {
        isUsingBar = false
    }
}
