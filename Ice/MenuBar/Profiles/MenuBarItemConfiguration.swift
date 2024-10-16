//
//  MenuBarItemConfiguration.swift
//  Ice
//

struct MenuBarItemConfiguration: Hashable {
    /// The items in the configuration, grouped by section name.
    private var groupedItems: [MenuBarSection.Name: [MenuBarItemInfo]]

    /// Returns the items for the section with the given name.
    ///
    /// - Parameter name: The name of the section of items to return.
    func getItems(for name: MenuBarSection.Name) -> [MenuBarItemInfo] {
        groupedItems[name, default: []]
    }

    /// Returns all items in the configuration, ordered by section.
    func getAllItems() -> [MenuBarItemInfo] {
        MenuBarSection.Name.allCases.reduce(into: []) { items, name in
            items.append(contentsOf: getItems(for: name))
        }
    }

    /// Returns all items in the configuration, ordered by section and delimited
    /// by the control items for the hidden and always-hidden sections.
    func getDelimitedItems() -> [MenuBarItemInfo] {
        MenuBarSection.Name.allCases.reduce(into: []) { items, name in
            items.append(contentsOf: getItems(for: name))
            switch name {
            case .visible:
                items.append(.hiddenControlItem)
            case .hidden:
                items.append(.alwaysHiddenControlItem)
            case .alwaysHidden:
                break
            }
        }
    }

    /// Returns all non-special items in the configuration, ordered by section.
    func getAllStandardItems() -> [MenuBarItemInfo] {
        getAllItems().filter { !$0.isSpecial }
    }

    /// Returns all non-special items in the configuration, ordered by section and
    /// delimited by the control items for the hidden and always-hidden sections.
    func getDelimitedStandardItems() -> [MenuBarItemInfo] {
        getDelimitedItems().filter { !$0.isSpecial }
    }

    /// Sets the items for the section with the given name.
    ///
    /// - Parameters:
    ///   - items: The items to set.
    ///   - name: The name of the section of items to set.
    mutating func setItems(_ items: [MenuBarItemInfo], for name: MenuBarSection.Name) {
        groupedItems[name] = items
    }

    /// Adds an item to the location of the ``MenuBarItemInfo/newItems`` special
    /// item in the configuration.
    mutating func addItem(_ item: MenuBarItemInfo) {
        validate()
        guard !MenuBarItemInfo.nonHideableItems.contains(item) else {
            return
        }
        guard !Set(getAllItems()).contains(item) else {
            return
        }
        for name in MenuBarSection.Name.allCases {
            var items = getItems(for: name)
            if let index = items.firstIndex(of: .newItems) {
                Logger.configuration.info("Adding \(item) to \(name.logString) section of profile")
                items.insert(item, at: index)
                setItems(items, for: name)
                break
            }
        }
    }
}

// MARK: MenuBarItemConfiguration Validation
extension MenuBarItemConfiguration {
    /// An operation that can occur during the validation of a configuration.
    enum ValidationOperation {
        case appendItem(MenuBarItemInfo, to: MenuBarSection.Name)
        case insertItem(MenuBarItemInfo, at: Int, in: MenuBarSection.Name)
    }

    /// Ensures the configuration is valid, updating it if necessary.
    mutating func validate() {
        let operations: [ValidationOperation] = [
            .appendItem(.newItems, to: .hidden),
        ]
        update(&groupedItems) { groupedItems in
            for operation in operations {
                let allItems = Set(groupedItems.values.joined())
                switch operation {
                case .appendItem(let item, to: let name) where !allItems.contains(item):
                    groupedItems[name, default: []].append(item)
                case .insertItem(let item, at: let index, in: let name) where !allItems.contains(item):
                    groupedItems[name, default: []].insert(item, at: index)
                default:
                    continue
                }
            }
            for name1 in MenuBarSection.Name.allCases {
                let items = Set(groupedItems[name1, default: []])
                for name2 in MenuBarSection.Name.allCases where name2 != name1 {
                    groupedItems[name2, default: []].removeAll(where: items.contains)
                }
            }
        }
    }
}

// MARK: MenuBarItemConfiguration Constructors
extension MenuBarItemConfiguration {
    /// An empty configuration.
    static let empty = MenuBarItemConfiguration(groupedItems: [:])

    /// Returns a configuration from the items currently in the menu bar.
    static func current() -> MenuBarItemConfiguration {
        var allItems = MenuBarItem.getMenuBarItems(onScreenOnly: false, activeSpaceOnly: true)

        guard let hiddenControlItem = allItems.firstIndex(of: .hiddenControlItem).map({ allItems.remove(at: $0) }) else {
            Logger.configuration.warning("Missing hidden control item, so returning empty configuration")
            return .empty
        }

        let alwaysHiddenControlItem = allItems.firstIndex(of: .alwaysHiddenControlItem).map({ allItems.remove(at: $0) })
        let predicates = Predicates.sectionPredicates(hiddenControlItem: hiddenControlItem, alwaysHiddenControlItem: alwaysHiddenControlItem)

        let isValidForConfiguration = Predicates.menuBarItemsForConfiguration()
        var groupedItems = [MenuBarSection.Name: [MenuBarItemInfo]]()

        for item in allItems.reversed() {
            guard isValidForConfiguration(item) else {
                Logger.configuration.debug("\(item.logString) not valid for configuration, so skipping")
                continue
            }
            if predicates.isInVisibleSection(item) {
                groupedItems[.visible, default: []].append(item.info)
            } else if predicates.isInHiddenSection(item) {
                groupedItems[.hidden, default: []].append(item.info)
            } else if predicates.isInAlwaysHiddenSection(item) {
                groupedItems[.alwaysHidden, default: []].append(item.info)
            } else {
                Logger.configuration.warning("\(item.logString) not added to configuration")
            }
        }

        return MenuBarItemConfiguration(groupedItems: groupedItems)
    }
}

// MARK: MenuBarItemConfiguration: Codable
extension MenuBarItemConfiguration: Codable {
    private enum CodingKeys: String, CodingKey {
        case visibleItems = "Visible"
        case hiddenItems = "Hidden"
        case alwaysHiddenItems = "AlwaysHidden"
    }

    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.groupedItems = try [
            .visible: container.decode(Array.self, forKey: .visibleItems),
            .hidden: container.decode(Array.self, forKey: .hiddenItems),
            .alwaysHidden: container.decode(Array.self, forKey: .alwaysHiddenItems),
        ]
    }

    func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(groupedItems[.visible, default: []], forKey: .visibleItems)
        try container.encode(groupedItems[.hidden, default: []], forKey: .hiddenItems)
        try container.encode(groupedItems[.alwaysHidden, default: []], forKey: .alwaysHiddenItems)
    }
}

// MARK: - Logger
private extension Logger {
    static let configuration = Logger(category: "MenuBarItemConfiguration")
}
