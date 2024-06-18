//
//  Sequence+sortedByOrderInMenuBar.swift
//  Ice
//

extension Sequence where Element == MenuBarItem {
    /// Returns the menu bar items, sorted by their order in the menu bar.
    func sortedByOrderInMenuBar() -> [MenuBarItem] {
        sorted { lhs, rhs in
            lhs.frame.maxX < rhs.frame.maxX
        }
    }
}
