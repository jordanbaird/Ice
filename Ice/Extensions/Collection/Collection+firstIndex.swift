//
//  Collection+firstIndex.swift
//  Ice
//

extension Collection where Element == MenuBarItem {
    /// Returns the first index where the menu bar item with the specified info
    /// appears in the collection.
    func firstIndex(of info: MenuBarItemInfo) -> Index? {
        firstIndex { $0.info == info }
    }
}
