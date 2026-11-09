//
//  SectionCountSummary.swift
//  Ice
//

/// What the layout editor shows for one section: the item count, the empty
/// state and, for the visible section, the note about items behind the notch.
struct SectionCountSummary: Equatable {
    let itemCount: Int
    /// Items of the visible section that the system pushed behind the notch
    /// of the current screen. Always 0 for the other sections.
    let behindNotchCount: Int

    init(itemCount: Int, behindNotchCount: Int = 0) {
        self.itemCount = max(itemCount, 0)
        // Can't hide more items than the section has.
        self.behindNotchCount = min(max(behindNotchCount, 0), self.itemCount)
    }

    var isEmpty: Bool { itemCount == 0 }

    var showsNotchNote: Bool { behindNotchCount > 0 }
}
