//
//  DisplayTopology.swift
//  Ice
//

import CoreGraphics

/// Describes changes in the set of connected displays and what to do about them.
enum DisplayTopology {
    struct Display: Equatable {
        let uuid: String
        let frame: CGRect
        let isBuiltIn: Bool
        let isMain: Bool
    }

    struct Change: Equatable {
        var added = [String]()
        var removed = [String]()
        var reconfigured = [String]()
        var mainChanged = false

        var isEmpty: Bool {
            added.isEmpty && removed.isEmpty && reconfigured.isEmpty && !mainChanged
        }
    }

    enum Reaction: Hashable, Comparable {
        case recache
        case invalidateGeometry
        case hideBar
    }

    static func diff(old: [Display], new: [Display]) -> Change {
        let oldByID = Dictionary(old.map { ($0.uuid, $0) }) { first, _ in first }
        let newByID = Dictionary(new.map { ($0.uuid, $0) }) { first, _ in first }
        var change = Change()
        change.added = newByID.keys.filter { oldByID[$0] == nil }.sorted()
        change.removed = oldByID.keys.filter { newByID[$0] == nil }.sorted()
        change.reconfigured = newByID.keys
            .filter { id in oldByID[id].map { $0.frame != newByID[id]?.frame } ?? false }
            .sorted()
        change.mainChanged = old.first(where: \.isMain)?.uuid != new.first(where: \.isMain)?.uuid
        return change
    }

    /// What to do after a change. `barDisplayUUID` is the display the Trincano
    /// Bar is currently on, if it is visible.
    static func reactions(to change: Change, barDisplayUUID: String?) -> [Reaction] {
        guard !change.isEmpty else {
            return []
        }
        var reactions: [Reaction] = [.recache, .invalidateGeometry]
        if let barDisplayUUID, change.removed.contains(barDisplayUUID) {
            reactions.append(.hideBar)
        }
        return reactions
    }
}
