//
//  MenuBarSearchModel.swift
//  Ice
//

import Combine
import Ifrit

@MainActor
final class MenuBarSearchModel: ObservableObject {
    enum ItemID: Hashable {
        case header(MenuBarSection.Name)
        case item(MenuBarItemTag)
    }

    typealias ListItem = SectionedListItem<ItemID>

    @Published var searchText = ""
    @Published var displayedItems = [ListItem]()
    @Published var selection: ItemID?

    let fuse = Fuse(threshold: 0.5)
}
