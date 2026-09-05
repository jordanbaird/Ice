//
//  MacOS27MenuBarController.swift
//  Ice
//

import Cocoa
import OSLog

/// Persists section assignments and explicit Layout edits on macOS 27.
/// This controller never intercepts input or restricts system visibility.
@MainActor
final class MacOS27MenuBarController {
    private typealias LayoutOwners = MacOS27LayoutOwnerRegistry<MenuBarItemTag.Namespace>
    private struct StoredLayout: Codable, Equatable {
        var assignments = [String: MenuBarSection.Name]()
        var order = [MenuBarSection.Name: [String]]()
    }

    // v3 discards layouts that included Ice's own visible control item. The Ice
    // button is the permanent toggle and must never be assigned to a section.
    private static let defaultsKey = "MacOS27MenuBarController.layout.v3"

    private let logger = Logger(category: "MacOS27MenuBarController")
    private var layout: StoredLayout
    private var persistedLayout: StoredLayout?
    private var snapshots = [String: MenuBarItem]()
    private var missingItemGrace = MacOS27MissingItemGrace()
    private var layoutOwners = LayoutOwners()
    private var knownBundleIdentifiers = [String: String]()
    private var lastLiveItems = [MenuBarItem]()
    private var lastSourceItems = [MenuBarItem]()
    private var lastManagedItems = [MenuBarItem]()
    private var sectionsWithPendingMove = Set<MenuBarSection.Name>()
    /// The exact item identities whose live left-to-right order must converge
    /// before Layout stops displaying a verified move's projected order.
    private var pendingPhysicalOrders = [MenuBarSection.Name: [String]]()
    private var isLayoutEditorPresented = false
    private(set) var isReorderInProgress = false {
        didSet {
            if isReorderInProgress != oldValue {
                interactionGeneration &+= 1
                if isLayoutEditing { onEditingChanged?() }
            }
        }
    }
    /// Invalidates captures that span an editor or reorder lifecycle change.
    private(set) var interactionGeneration: UInt = 0

    /// Layout is the only context in which Ice may rearrange status items.
    private(set) var isLayoutEditing = false {
        didSet {
            if isLayoutEditing != oldValue {
                if isLayoutEditing {
                    layoutOwners.begin(
                        knownOwners: owners(of: knownItemsForReordering()),
                        runningOwners: runningOwners()
                    )
                } else {
                    layoutOwners.end()
                }
                interactionGeneration &+= 1
                onEditingChanged?()
            }
        }
    }

    var onEditingChanged: (() -> Void)?

    /// Concealed overflow items can report coincident AX frames. Retain the
    /// saved order until Layout has exposed their real positions again.
    var isConcealingItems = false

    init() {
        if
            let data = UserDefaults.standard.data(forKey: Self.defaultsKey),
            let stored = try? JSONDecoder().decode(StoredLayout.self, from: data)
        {
            self.layout = stored
            self.persistedLayout = stored
            // Process-local AX tokens cannot identify items after a restart.
            layout.assignments = layout.assignments.filter {
                !MacOS27RuntimeItemIdentity.isStoredIdentifier($0.key)
            }
            for section in MenuBarSection.Name.allCases {
                layout.order[section]?.removeAll(where: MacOS27RuntimeItemIdentity.isStoredIdentifier)
            }
        } else {
            self.layout = StoredLayout()
        }
    }

    func makeCache(
        liveItems: [MenuBarItem],
        sourceItems: [MenuBarItem],
        displayID: CGDirectDisplayID?
    ) -> MenuBarItemManager.ItemCache {
        precondition(Thread.isMainThread)
        migrateTextInputIdentityIfNeeded(in: liveItems)
        seedUnassignedItems(liveItems, using: sourceItems)
        if !isReorderInProgress,
           let iceItem = sourceItems.first(matching: .visibleControlItem) {
            let alwaysBoundary = sourceItems.first(matching: .nativeBoundary(for: .alwaysHidden))
            // The native bar, including manual Command-drags, is authoritative.
            for item in liveItems {
                let identifier = item.tag.persistentIdentifier
                guard let side = MacOS27NativeBoundary.side(of: item.bounds, relativeTo: iceItem.bounds) else {
                    continue // Off-bar overflow frames are not native order evidence.
                }
                if side == .right {
                    layout.assignments[identifier] = .visible
                } else if isConcealingItems {
                    continue // Keep concealed left-hand assignments until revealed.
                } else if let alwaysBoundary, item.bounds.minX < alwaysBoundary.bounds.minX {
                    layout.assignments[identifier] = .alwaysHidden
                } else if item.bounds.minX < iceItem.bounds.minX,
                          alwaysBoundary != nil || layout.assignments[identifier] != .alwaysHidden {
                    layout.assignments[identifier] = .hidden
                }
            }
        }
        lastLiveItems = liveItems
        lastSourceItems = sourceItems
        layoutOwners.observe(owners(of: sourceItems))

        for item in sourceItems {
            let identifier = item.tag.persistentIdentifier
            if let bundleIdentifier = bundleIdentifier(for: item) {
                knownBundleIdentifiers[identifier] = bundleIdentifier
            }
        }
        for item in liveItems {
            let identifier = item.tag.persistentIdentifier
            snapshots[identifier] = item
            missingItemGrace.saw(identifier)
            if let bundleIdentifier = bundleIdentifier(for: item) {
                knownBundleIdentifiers[identifier] = bundleIdentifier
            }
        }

        let runningBundleIdentifiers = Set(
            NSWorkspace.shared.runningApplications.compactMap(\.bundleIdentifier)
        )
        var itemsByIdentifier = Dictionary(
            liveItems.map { ($0.tag.persistentIdentifier, $0) },
            uniquingKeysWith: { current, _ in current }
        )

        // Concealment and AX reflow can omit a live item. Conversely, a running
        // plugin host can intentionally withdraw only one item. Retain through
        // concealment/reorder; while expanded, give omissions a grace period
        // and then require a successful owner reread before retiring a tile.
        let canObserveMissing = !isConcealingItems && !isReorderInProgress &&
            sourceItems.first(matching: .visibleControlItem) != nil
        let now = ProcessInfo.processInfo.systemUptime
        var candidates = [MenuBarItem]()
        var retiredIdentifiers = Set<String>()
        for (identifier, item) in snapshots where itemsByIdentifier[identifier] == nil {
            let ownerIsAvailable = if let bundleIdentifier = knownBundleIdentifiers[identifier] {
                runningBundleIdentifiers.contains(bundleIdentifier)
            } else {
                false
            }
            guard ownerIsAvailable else {
                retiredIdentifiers.insert(identifier)
                continue
            }
            if missingItemGrace.needsVerification(identifier, canObserve: canObserveMissing, now: now) {
                candidates.append(item)
            }
            itemsByIdentifier[identifier] = item
        }
        if #available(macOS 27.0, *), !candidates.isEmpty {
            retiredIdentifiers.formUnion(MacOS27MenuBarItemProvider.confirmedAbsentIdentifiers(for: candidates))
        }
        for identifier in retiredIdentifiers {
            snapshots.removeValue(forKey: identifier)
            itemsByIdentifier.removeValue(forKey: identifier)
            knownBundleIdentifiers.removeValue(forKey: identifier)
            missingItemGrace.saw(identifier)
            if MacOS27RuntimeItemIdentity.isStoredIdentifier(identifier) {
                layout.assignments.removeValue(forKey: identifier)
                for section in MenuBarSection.Name.allCases {
                    layout.order[section]?.removeAll { $0 == identifier }
                }
            }
        }
        lastManagedItems = Array(itemsByIdentifier.values)

        var cache = MenuBarItemManager.ItemCache(displayID: displayID)
        let liveIdentifiers = Set(liveItems.map { $0.tag.persistentIdentifier })
        for section in MenuBarSection.Name.allCases {
            let savedOrder = layout.order[section, default: []]
            let unorderedItems = itemsByIdentifier.values.filter { item in
                layout.assignments[item.tag.persistentIdentifier, default: .visible] == section
            }
            let sectionItems: [MenuBarItem]

            if sectionsWithPendingMove.contains(section) {
                let savedIndices = Dictionary(
                    uniqueKeysWithValues: savedOrder.enumerated().map { ($0.element, $0.offset) }
                )
                sectionItems = unorderedItems.sorted { lhs, rhs in
                    let lhsIndex = savedIndices[lhs.tag.persistentIdentifier]
                    let rhsIndex = savedIndices[rhs.tag.persistentIdentifier]
                    switch (lhsIndex, rhsIndex) {
                    case let (lhsIndex?, rhsIndex?): return lhsIndex < rhsIndex
                    case (_?, nil): return true
                    case (nil, _?): return false
                    case (nil, nil): return Self.isOrderedLeftToRight(lhs, rhs)
                    }
                }
            } else if !isConcealingItems,
                unorderedItems.allSatisfy({ liveIdentifiers.contains($0.tag.persistentIdentifier) }) {
                // AX bounds are the source of truth for anything the user can
                // currently see in the real menu bar.
                sectionItems = unorderedItems.sorted(by: Self.isOrderedLeftToRight)
            } else {
                // Preserve the last explicit drag order for an item whose
                // private MenuBarAgent key cannot be resolved.
                let savedIndices = Dictionary(
                    uniqueKeysWithValues: savedOrder.enumerated().map { ($0.element, $0.offset) }
                )
                sectionItems = unorderedItems.sorted { lhs, rhs in
                    let lhsIndex = savedIndices[lhs.tag.persistentIdentifier]
                    let rhsIndex = savedIndices[rhs.tag.persistentIdentifier]
                    switch (lhsIndex, rhsIndex) {
                    case let (lhsIndex?, rhsIndex?): return lhsIndex < rhsIndex
                    case (_?, nil): return true
                    case (nil, _?): return false
                    case (nil, nil): return Self.isOrderedLeftToRight(lhs, rhs)
                    }
                }
            }
            cache[section] = sectionItems

            // Preserve absent identifiers in their saved slots. A running app
            // can temporarily withdraw or republish a status item, and one
            // incomplete AX snapshot must not erase the user's order. Explicit
            // moves already remove an identifier from every old section before
            // inserting it into the destination, so this cannot undo a drag.
            var updatedOrder = sectionItems.map { $0.tag.persistentIdentifier }
            for (savedIndex, identifier) in savedOrder.enumerated()
            where layout.assignments[identifier] == section && !updatedOrder.contains(identifier) {
                updatedOrder.insert(identifier, at: min(savedIndex, updatedOrder.endIndex))
            }
            layout.order[section] = updatedOrder
        }

        persist()
        return cache
    }

    func move(
        item: MenuBarItem,
        to destination: MenuBarItemManager.MoveDestination,
        currentCache: MenuBarItemManager.ItemCache,
        requiredSection: MenuBarSection.Name? = nil
    ) -> MenuBarSection.Name {
        guard #available(macOS 27.0, *) else { return .visible }

        let identifier = item.tag.persistentIdentifier
        let target = destination.targetItem
        let targetIdentifier = target.tag.persistentIdentifier
        let targetSection: MenuBarSection.Name
        let previousSection = layout.assignments[identifier, default: .visible]

        if let requiredSection {
            // A Layout drop already carries the destination container. Do
            // not infer it again from the target item: an empty Hidden section
            // is represented physically by the visible Ice control item, so
            // geometry alone would incorrectly persist the moved item as
            // Visible after a successful cross-boundary drag.
            targetSection = requiredSection
        } else if target.tag == .hiddenControlItem {
            targetSection = switch destination {
            case .leftOfItem: .hidden
            case .rightOfItem: .visible
            }
        } else if target.tag == .alwaysHiddenControlItem {
            targetSection = switch destination {
            case .leftOfItem: .alwaysHidden
            case .rightOfItem: .hidden
            }
        } else if let address = currentCache.address(for: target.tag) {
            targetSection = address.section
        } else {
            targetSection = .visible
        }

        for section in MenuBarSection.Name.allCases {
            layout.order[section, default: []].removeAll { $0 == identifier }
        }
        layout.assignments[identifier] = targetSection

        if target.isControlItem {
            switch destination {
            case .leftOfItem:
                layout.order[targetSection, default: []].append(identifier)
            case .rightOfItem:
                layout.order[targetSection, default: []].insert(identifier, at: 0)
            }
        } else {
            var order = layout.order[targetSection, default: []]
            let targetIndex = order.firstIndex(of: targetIdentifier) ?? order.endIndex
            let insertionIndex = switch destination {
            case .leftOfItem: targetIndex
            case .rightOfItem: min(targetIndex + 1, order.endIndex)
            }
            order.insert(identifier, at: insertionIndex)
            layout.order[targetSection] = order
        }

        snapshots[identifier] = item
        sectionsWithPendingMove.formUnion([previousSection, targetSection])
        for section in Set([previousSection, targetSection]) {
            var relevantIdentifiers = Set(
                currentCache[section].map { $0.tag.persistentIdentifier }
            )
            if section == previousSection {
                relevantIdentifiers.remove(identifier)
            }
            if section == targetSection {
                relevantIdentifiers.insert(identifier)
            }
            pendingPhysicalOrders[section] = layout.order[section, default: []].filter(
                relevantIdentifiers.contains
            )
        }
        persist()
        return targetSection
    }

    func move(
        item: MenuBarItem,
        to section: MenuBarSection.Name,
        currentCache: MenuBarItemManager.ItemCache
    ) {
        guard #available(macOS 27.0, *) else { return }

        let identifier = item.tag.persistentIdentifier
        let previousSection = layout.assignments[identifier, default: .visible]
        for existingSection in MenuBarSection.Name.allCases {
            layout.order[existingSection, default: []].removeAll { $0 == identifier }
        }
        layout.assignments[identifier] = section
        if section == .visible {
            // A section-only move targets the first slot immediately to the
            // right of Ice. Persist that same slot so the projected Layout
            // order agrees with the native position and can converge without
            // a multi-second refresh loop.
            layout.order[section, default: []].insert(identifier, at: 0)
        } else {
            // Hidden section-only moves target the last slot immediately to
            // the left of Ice.
            layout.order[section, default: []].append(identifier)
        }
        snapshots[identifier] = item
        sectionsWithPendingMove.formUnion([previousSection, section])
        for pendingSection in Set([previousSection, section]) {
            var relevantIdentifiers = Set(
                currentCache[pendingSection].map { $0.tag.persistentIdentifier }
            )
            if pendingSection == previousSection {
                relevantIdentifiers.remove(identifier)
            }
            if pendingSection == section {
                relevantIdentifiers.insert(identifier)
            }
            pendingPhysicalOrders[pendingSection] = layout.order[pendingSection, default: []].filter(
                relevantIdentifiers.contains
            )
        }
        persist()
    }

    func completePendingMove() {
        sectionsWithPendingMove.removeAll()
        pendingPhysicalOrders.removeAll()
    }

    /// Returns true only after one complete live AX snapshot contains every
    /// item involved in the move and their physical order matches the saved
    /// target. Until then Layout keeps the verified projected order, avoiding
    /// an old/new/old visual oscillation while MenuBarAgent republishes scenes.
    func pendingMoveHasConverged() -> Bool {
        guard !pendingPhysicalOrders.isEmpty else { return true }

        for expectedOrder in pendingPhysicalOrders.values {
            let expectedIdentifiers = Set(expectedOrder)
            let liveOrder = lastLiveItems
                .filter { expectedIdentifiers.contains($0.tag.persistentIdentifier) }
                .sorted(by: Self.isOrderedLeftToRight)
                .map { $0.tag.persistentIdentifier }
            guard liveOrder == expectedOrder else { return false }
        }
        return true
    }

    func beginLayoutEditing() {
        guard #available(macOS 27.0, *) else { return }
        isLayoutEditorPresented = true
        isLayoutEditing = true
    }

    func endLayoutEditing() {
        guard #available(macOS 27.0, *) else { return }
        isLayoutEditorPresented = false
        guard !isReorderInProgress else { return }
        isLayoutEditing = false
        completePendingMove()
    }

    /// Keeps the editing session active until the requested order is reconciled.
    func beginReordering() {
        guard #available(macOS 27.0, *) else { return }
        isReorderInProgress = true
        isLayoutEditing = true
    }

    /// Ends the reorder session without changing visibility or system input.
    func endReordering() {
        guard #available(macOS 27.0, *) else { return }
        isReorderInProgress = false
        guard !isLayoutEditorPresented else { return }
        isLayoutEditing = false
        completePendingMove()
    }

    /// Returns the latest live AX snapshot without starting another complete
    /// menu-bar walk. Layout reordering uses this to keep its fast path local.
    func liveItemsForReordering() -> [MenuBarItem] {
        lastLiveItems
    }

    /// Includes retained concealed-item snapshots so their preferred ranks can
    /// be updated even while MenuBarAgent has removed them from AX.
    func knownItemsForReordering() -> [MenuBarItem] {
        Array(
            Dictionary(
                (Array(snapshots.values) + lastSourceItems + lastManagedItems + lastLiveItems).map {
                    ($0.tag.persistentIdentifier, $0)
                },
                // Later arrays are progressively fresher. Never let a retained
                // concealed snapshot overwrite a newly published AX frame.
                uniquingKeysWith: { _, newer in newer }
            ).values
        )
    }

    /// Called by the existing workspace publisher, before its cache trigger.
    /// New app lifetimes join only this Layout session's targeted AX reads.
    func runningApplicationsChanged(_ applications: [NSRunningApplication]) {
        guard isLayoutEditing else { return }
        layoutOwners.runningApplicationsChanged(Set(applications.compactMap { owner(for: $0) }))
    }

    func ownersForLayoutRefresh() -> (sourcePIDs: Set<pid_t>, namespaces: Set<MenuBarItemTag.Namespace>) {
        layoutOwners.targets(runningOwners: runningOwners())
    }

    private func runningOwners() -> Set<LayoutOwners.Owner> {
        Set(NSWorkspace.shared.runningApplications.compactMap { owner(for: $0) })
    }

    private func owners(of items: [MenuBarItem]) -> Set<LayoutOwners.Owner> {
        Set(items.compactMap { item in
            guard let app = NSRunningApplication(processIdentifier: item.sourcePID ?? item.ownerPID),
                  let owner = owner(for: app), owner.namespace == item.tag.namespace else { return nil }
            return owner
        })
    }

    private func owner(for app: NSRunningApplication) -> LayoutOwners.Owner? {
        guard !app.isTerminated else { return nil }
        let namespace: MenuBarItemTag.Namespace = switch app.bundleIdentifier {
        case "com.apple.MenuBarAgent": .controlCenter
        case Constants.bundleIdentifier: .ice
        case let bundleIdentifier?: .string(bundleIdentifier)
        case nil: .optional(app.localizedName)
        }
        return LayoutOwners.Owner(
            pid: app.processIdentifier,
            namespace: namespace,
            launchTime: app.launchDate?.timeIntervalSinceReferenceDate
        )
    }

    private func persist() {
        guard layout != persistedLayout, let data = try? JSONEncoder().encode(layout) else { return }
        UserDefaults.standard.set(data, forKey: Self.defaultsKey)
        persistedLayout = layout
    }

    /// Collapses legacy input-source labels into TextInputMenuAgent's stable
    /// Item-N identity without changing the user's section or position.
    private func migrateTextInputIdentityIfNeeded(in items: [MenuBarItem]) {
        for item in items where item.tag.namespace == .textInputMenuAgent {
            let canonicalIdentifier = item.tag.persistentIdentifier
            let namespacePrefix = "\(item.tag.namespace):"
            let instanceSuffix = "#\(item.tag.instanceIndex)"
            let aliases = Set(layout.assignments.keys.filter {
                $0.hasPrefix(namespacePrefix) && $0.hasSuffix(instanceSuffix)
            }).union([canonicalIdentifier])
            guard aliases.contains(where: { $0 != canonicalIdentifier }) else { continue }

            var savedLocation: (section: MenuBarSection.Name, index: Int)?
            for section in MenuBarSection.Name.allCases {
                if let index = layout.order[section, default: []].firstIndex(where: aliases.contains) {
                    savedLocation = (section, index)
                    break
                }
            }
            let section = savedLocation?.section
                ?? layout.assignments[canonicalIdentifier]
                ?? aliases.compactMap { layout.assignments[$0] }.first
                ?? .visible

            for alias in aliases {
                layout.assignments.removeValue(forKey: alias)
            }
            layout.assignments[canonicalIdentifier] = section

            for existingSection in MenuBarSection.Name.allCases {
                layout.order[existingSection, default: []].removeAll(where: aliases.contains)
            }
            let insertionIndex = min(
                savedLocation?.index ?? layout.order[section, default: []].endIndex,
                layout.order[section, default: []].endIndex
            )
            layout.order[section, default: []].insert(canonicalIdentifier, at: insertionIndex)
            logger.notice("Migrated Text Input menu bar identity to \(canonicalIdentifier, privacy: .public)")
        }
    }

    private static func isOrderedLeftToRight(_ lhs: MenuBarItem, _ rhs: MenuBarItem) -> Bool {
        if lhs.bounds.minX == rhs.bounds.minX {
            return lhs.bounds.minY < rhs.bounds.minY
        }
        return lhs.bounds.minX < rhs.bounds.minX
    }

    /// Migrates Ice's physical divider layout into macOS 27's explicit section
    /// assignments. Without this, a first launch treats every existing item as
    /// visible until the user manually rebuilds the entire layout.
    private func seedUnassignedItems(
        _ items: [MenuBarItem],
        using sourceItems: [MenuBarItem]
    ) {
        let hiddenDivider = sourceItems.first(matching: .visibleControlItem)
            ?? sourceItems.first(matching: .hiddenControlItem)
        let alwaysHiddenDivider = sourceItems.first(matching: .nativeBoundary(for: .alwaysHidden))
            ?? sourceItems.first(matching: .alwaysHiddenControlItem)

        var seededAnyItem = false
        for item in items {
            let identifier = item.tag.persistentIdentifier
            guard layout.assignments[identifier] == nil else { continue }

            let section: MenuBarSection.Name
            if let hiddenDivider, item.bounds.minX >= hiddenDivider.bounds.maxX {
                section = .visible
            } else if
                let hiddenDivider,
                let alwaysHiddenDivider,
                item.bounds.maxX <= hiddenDivider.bounds.minX,
                item.bounds.minX >= alwaysHiddenDivider.bounds.maxX
            {
                section = .hidden
            } else if
                let alwaysHiddenDivider,
                item.bounds.maxX <= alwaysHiddenDivider.bounds.minX
            {
                section = .alwaysHidden
            } else if let hiddenDivider, item.bounds.maxX <= hiddenDivider.bounds.minX {
                section = .hidden
            } else {
                section = .visible
            }

            layout.assignments[identifier] = section
            layout.order[section, default: []].append(identifier)
            seededAnyItem = true
        }

        guard seededAnyItem else { return }
        let visibleCount = layout.assignments.values.count { $0 == .visible }
        let hiddenCount = layout.assignments.values.count { $0 == .hidden }
        let alwaysHiddenCount = layout.assignments.values.count { $0 == .alwaysHidden }
        logger.notice(
            "Seeded macOS 27 layout: visible=\(visibleCount, privacy: .public), hidden=\(hiddenCount, privacy: .public), alwaysHidden=\(alwaysHiddenCount, privacy: .public)"
        )
    }

    private func bundleIdentifier(for item: MenuBarItem) -> String? {
        if item.tag.namespace == .controlCenter {
            return "com.apple.MenuBarAgent"
        }
        if case .string(let bundleIdentifier) = item.tag.namespace {
            return bundleIdentifier
        }
        return item.sourceApplication?.bundleIdentifier ?? item.owningApplication?.bundleIdentifier
    }
}
