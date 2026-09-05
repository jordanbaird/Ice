//
//  MenuBarItemManager.swift
//  Ice
//

import Cocoa
import Combine
import OSLog
import Semaphore

/// Manager for menu bar items.
@MainActor
final class MenuBarItemManager: ObservableObject {
    /// The current cache of menu bar items.
    @Published private(set) var itemCache = ItemCache(displayID: nil)

    /// Logger for the menu bar item manager.
    private nonisolated let logger = Logger.menuBarItemManager

    /// Semaphore to prevent overlapping event operations.
    private nonisolated let eventSemaphore = AsyncSemaphore(value: 1)

    /// Serializes each complete macOS 27 read/drag/verify transaction. Rapid
    /// Layout drops must not overlap native Command-drags or verify against an
    /// intermediate MenuBarAgent order.
    private let macOS27MoveSemaphore = AsyncSemaphore(value: 1)

    /// Actor for managing menu bar item cache operations.
    private let cacheActor = CacheActor()

    /// Contexts for temporarily shown menu bar items.
    private var temporarilyShownItemContexts = [TemporarilyShownItemContext]()

    /// A timer for rehiding temporarily shown menu bar items.
    private var rehideTimer: Timer?

    /// Timestamp of the most recent menu bar item move operation.
    private var lastMoveOperationTimestamp: ContinuousClock.Instant?

    /// The exact Layout order requested by the in-flight macOS 27 move.
    ///
    /// A complete AX cache walk can already be running when the user drops an
    /// item. Keep that stale walk useful for controller snapshots, but never
    /// let it republish the pre-move order over Layout while the physical
    /// transaction is still being read and verified.
    private var macOS27ProjectedCache: ItemCache?

    /// The latest complete Layout order requested by the user.
    ///
    /// Layout can accept another drag while MenuBarAgent is still settling the
    /// previous native Command-drag. Keep only this final state on screen and
    /// reconcile the physical menu bar toward it; never replay every
    /// intermediate drop as an independent transaction.
    private var macOS27DesiredCache: ItemCache?

    /// Source items that can affect the latest desired order. A newer request
    /// for the same item replaces its older generation in place.
    private var macOS27PendingMoveOrder = [MenuBarItemTag]()
    private var macOS27PendingMoveGenerations = [MenuBarItemTag: UInt64]()
    private var macOS27TouchedMoveTags = Set<MenuBarItemTag>()
    private var macOS27DesiredGeneration: UInt64 = 0

    /// The single worker that turns the latest Layout state into physical menu
    /// bar order. Unlike the move semaphore, this also coalesces queued intent.
    private var macOS27ReorderTask: Task<Void, Never>?

    /// Cached timeouts for move operations.
    private var moveOperationTimeouts = [MenuBarItemTag: Duration]()

    /// Storage for internal observers.
    private var cancellables = Set<AnyCancellable>()

    /// The shared app state.
    private(set) weak var appState: AppState?

    /// Sets up the manager.
    func performSetup(with appState: AppState) async {
        self.appState = appState
        await cacheItemsRegardless()
        configureCancellables(with: appState)
    }

    /// Configures the internal observers for the manager.
    private func configureCancellables(with appState: AppState) {
        var c = Set<AnyCancellable>()

        NSWorkspace.shared.publisher(for: \.runningApplications)
            .delay(for: 0.25, scheduler: DispatchQueue.main)
            .handleEvents(receiveOutput: { [weak appState] applications in
                if #available(macOS 27.0, *) {
                    appState?.menuBarManager.macOS27Controller.runningApplicationsChanged(applications)
                }
            })
            .discardMerge(Timer.publish(every: 5, on: .main, in: .default).autoconnect())
            .debounce(for: 1, scheduler: DispatchQueue.main)
            .sink { [weak self] in
                guard let self else {
                    return
                }
                Task {
                    await self.cacheItemsIfNeeded()
                }
            }
            .store(in: &c)

        appState.navigationState.$settingsNavigationIdentifier
            .sink { [weak self] identifier in
                guard let self else { return }
                if #available(macOS 27.0, *) {
                    if identifier == .menuBarLayout {
                        // Mark Layout editing before its navigation-triggered
                        // cache task starts. Otherwise that task performs a
                        // complete AX walk and can hold the provider lock while
                        // the user has already begun dragging.
                        appState.menuBarManager.macOS27Controller.beginLayoutEditing()
                    } else if appState.menuBarManager.macOS27Controller.isLayoutEditing {
                        // A restored Settings window can change panes without
                        // constructing the old Layout view long enough for its
                        // `onDisappear` callback to run.
                        appState.menuBarManager.macOS27Controller.endLayoutEditing()
                    }
                }
                guard identifier == .menuBarLayout else { return }
                Task {
                    await self.cacheItemsRegardless()
                }
            }
            .store(in: &c)

        cancellables = c
    }

    /// Returns a Boolean value that indicates whether the most recent
    /// menu bar item move operation occurred within the given duration.
    func lastMoveOperationOccurred(within duration: Duration) -> Bool {
        guard let timestamp = lastMoveOperationTimestamp else {
            return false
        }
        return timestamp.duration(to: .now) <= duration
    }
}

// MARK: - Item Cache

extension MenuBarItemManager {
    /// An actor that manages menu bar item cache operations.
    private final actor CacheActor {
        /// Stored task for the current cache operation.
        private var cacheTask: Task<Void, Never>?

        /// A list of the menu bar item window identifiers at the time
        /// of the previous cache.
        private(set) var cachedItemWindowIDs = [CGWindowID]()

        /// Runs the given async closure as a task and waits for it to
        /// complete before returning.
        ///
        /// If a task from a previous call to this method is currently
        /// running, that task is cancelled and replaced.
        func runCacheTask(_ operation: @escaping () async -> Void) async {
            cacheTask.take()?.cancel()
            let task = Task(operation: operation)
            cacheTask = task
            await withTaskCancellationHandler {
                await task.value
            } onCancel: {
                task.cancel()
            }
        }

        /// Updates the list of cached menu bar item window identifiers.
        func updateCachedItemWindowIDs(_ itemWindowIDs: [CGWindowID]) {
            cachedItemWindowIDs = itemWindowIDs
        }

        /// Clears the list of cached menu bar item window identifiers.
        func clearCachedItemWindowIDs() {
            cachedItemWindowIDs.removeAll()
        }
    }

    /// Cache for menu bar items.
    struct ItemCache: Hashable {
        /// Storage for cached menu bar items, keyed by section.
        private var storage = [MenuBarSection.Name: [MenuBarItem]]()

        /// The identifier of the display with the active menu bar at
        /// the time this cache was created.
        let displayID: CGDirectDisplayID?

        /// The cached menu bar items as an array.
        var managedItems: [MenuBarItem] {
            MenuBarSection.Name.allCases.reduce(into: []) { result, section in
                guard let items = storage[section] else {
                    return
                }
                result.append(contentsOf: items)
            }
        }

        /// Creates a cache with the given display identifier.
        init(displayID: CGDirectDisplayID?) {
            self.displayID = displayID
        }

        // TODO: This is redundant now, so remove it.
        /// Returns the managed menu bar items for the given section.
        func managedItems(for section: MenuBarSection.Name) -> [MenuBarItem] {
            self[section]
        }

        /// Returns the address for the menu bar item with the given tag,
        /// if it exists in the cache.
        func address(for tag: MenuBarItemTag) -> (section: MenuBarSection.Name, index: Int)? {
            for (section, items) in storage {
                guard let index = items.firstIndex(matching: tag) else {
                    continue
                }
                return (section, index)
            }
            return nil
        }

        /// Inserts the given menu bar item into the cache at the specified
        /// destination.
        mutating func insert(_ item: MenuBarItem, at destination: MoveDestination) {
            let targetTag = destination.targetItem.tag

            if targetTag == .hiddenControlItem {
                switch destination {
                case .leftOfItem:
                    self[.hidden].append(item)
                case .rightOfItem:
                    self[.visible].insert(item, at: 0)
                }
                return
            }

            if targetTag == .alwaysHiddenControlItem {
                switch destination {
                case .leftOfItem:
                    self[.alwaysHidden].append(item)
                case .rightOfItem:
                    self[.hidden].insert(item, at: 0)
                }
                return
            }

            guard case (let section, var index)? = address(for: targetTag) else {
                return
            }

            if case .rightOfItem = destination {
                let range = self[section].startIndex...self[section].endIndex
                index = (index + 1).clamped(to: range)
            }

            self[section].insert(item, at: index)
        }

        /// Accesses the items in the given section.
        subscript(section: MenuBarSection.Name) -> [MenuBarItem] {
            get { storage[section, default: []] }
            set { storage[section] = newValue }
        }
    }

    /// A pair of control items, taken from a list of menu bar items
    /// during a menu bar item cache operation.
    private struct ControlItemPair {
        let hidden: MenuBarItem
        let alwaysHidden: MenuBarItem?

        init?(items: inout [MenuBarItem]) {
            guard let hidden = items.removeFirst(matching: .hiddenControlItem) else {
                return nil
            }
            self.hidden = hidden
            self.alwaysHidden = items.removeFirst(matching: .alwaysHiddenControlItem)
        }
    }

    /// Context maintained during a menu bar item cache operation.
    private struct CacheContext {
        let controlItems: ControlItemPair

        var cache: ItemCache
        var temporarilyShownItems = [(MenuBarItem, MoveDestination)]()
        var shouldClearCachedItemWindowIDs = false

        private(set) lazy var hiddenControlItemBounds = bestBounds(for: controlItems.hidden)
        private(set) lazy var alwaysHiddenControlItemBounds = controlItems.alwaysHidden.map(bestBounds)

        init(controlItems: ControlItemPair, displayID: CGDirectDisplayID?) {
            self.controlItems = controlItems
            self.cache = ItemCache(displayID: displayID)
        }

        func bestBounds(for item: MenuBarItem) -> CGRect {
            Bridging.getWindowBounds(for: item.windowID) ?? item.bounds
        }

        func isValidForCaching(_ item: MenuBarItem) -> Bool {
            if !item.canBeHidden {
                return false
            }
            if item.isSystemClone {
                return false
            }
            if item.isControlItem, item.tag != .visibleControlItem {
                return false
            }
            return true
        }

        mutating func findSection(for item: MenuBarItem) -> MenuBarSection.Name? {
            lazy var itemBounds = bestBounds(for: item)
            return MenuBarSection.Name.allCases.first { section in
                switch section {
                case .visible:
                    return itemBounds.minX >= hiddenControlItemBounds.maxX
                case .hidden:
                    if let alwaysHiddenControlItemBounds {
                        return itemBounds.maxX <= hiddenControlItemBounds.minX &&
                        itemBounds.minX >= alwaysHiddenControlItemBounds.maxX
                    } else {
                        return itemBounds.maxX <= hiddenControlItemBounds.minX
                    }
                case .alwaysHidden:
                    if let alwaysHiddenControlItemBounds {
                        return itemBounds.maxX <= alwaysHiddenControlItemBounds.minX
                    } else {
                        return false
                    }
                }
            }
        }
    }

    /// Caches the given menu bar items, without ensuring that the provided
    /// control items are correctly ordered.
    private func uncheckedCacheItems(
        items: [MenuBarItem],
        controlItems: ControlItemPair,
        displayID: CGDirectDisplayID?
    ) async {
        var context = CacheContext(controlItems: controlItems, displayID: displayID)

        for item in items where context.isValidForCaching(item) {
            if item.sourcePID == nil {
                logger.warning("Missing sourcePID for \(item.logString, privacy: .public)")
                context.shouldClearCachedItemWindowIDs = true
            }

            if let temp = temporarilyShownItemContexts.first(where: { $0.tag == item.tag }) {
                // Cache temporarily shown items as if they were in their original locations.
                // Keep track of them separately and use their return destinations to insert
                // them into the cache once all other items have been handled.
                context.temporarilyShownItems.append((item, temp.returnDestination))
                continue
            }

            if let section = context.findSection(for: item) {
                context.cache[section].append(item)
                continue
            }

            logger.warning("Couldn't find section for caching \(item.logString, privacy: .public)")
            context.shouldClearCachedItemWindowIDs = true
        }

        for (item, destination) in context.temporarilyShownItems {
            context.cache.insert(item, at: destination)
        }

        if context.shouldClearCachedItemWindowIDs {
            logger.info("Clearing cached menu bar item windowIDs")
            await cacheActor.clearCachedItemWindowIDs() // Ensure next cache isn't skipped.
        }

        guard itemCache != context.cache else {
            logger.debug("Not updating menu bar item cache, as items haven't changed")
            return
        }

        itemCache = context.cache
        logger.debug("Updated menu bar item cache")
    }

    /// Accept a user's native Command-drag before hiding. Ice's visible button
    /// is the sole divider: repair only our own blank item if the user dropped
    /// between the pair, then read membership from the expanded physical order.
    @available(macOS 27.0, *)
    func alignNativeHidingBoundary(updatingCache: Bool, displayID: CGDirectDisplayID? = nil) async -> Bool {
        guard let appState else { return false }
        let controller = appState.menuBarManager.macOS27Controller
        // An ordinary click does not need a fixed settling delay or an AX
        // walk through other applications when our native pair is already
        // ready. Never use saved positions or retained frames for this check.
        if let displayID,
           !controller.isLayoutEditing,
           !appState.settings.advanced.enableAlwaysHiddenSection,
           !Task.isCancelled {
            // Normally ready in this event turn. A freshly hosted scene may
            // need one or two display frames, not an unconditional 200 ms.
            for attempt in 0 ..< 3 {
                if attempt > 0 {
                    do { try await Task.sleep(for: .milliseconds(16)) } catch { return false }
                }
                guard !Task.isCancelled else { return false }
                if nativeHidingBoundaryIsReady(on: displayID) {
                    return true
                }
            }
        }
        // Reinsertion changes native hit regions before AX updates all owners.
        // Let that one layout transaction finish before resolving a drag.
        do { try await Task.sleep(for: .milliseconds(200)) } catch { return false }
        var snapshot = await currentMacOS27ReorderSnapshot(appState: appState)
        // A withdrawn boundary takes a short native layout pass to reappear.
        // Never substitute a retained (possibly concealed) frame for this read.
        for _ in 0 ..< 6 where snapshot.first(matching: .nativeBoundary(for: .hidden)) == nil {
            do { try await Task.sleep(for: .milliseconds(35)) } catch { return false }
            snapshot = await currentMacOS27ReorderSnapshot(appState: appState)
        }
        guard !Task.isCancelled,
              let ice = snapshot.first(matching: .visibleControlItem),
              let boundary = snapshot.first(matching: .nativeBoundary(for: .hidden)) else { return false }

        let destination = MoveDestination.leftOfItem(ice)
        let order = snapshot.sorted { $0.bounds.minX < $1.bounds.minX }.map(\.tag)
        logger.notice("Preparing native boundary \(boundary.bounds.debugDescription, privacy: .public) beside Ice \(ice.bounds.debugDescription, privacy: .public)")
        if !MacOS27NativeBoundary.isImmediatelyBefore(boundary.tag, ice.tag, in: order) {
            guard await performMacOS27NativeMove(
                item: boundary,
                destination: destination,
                contextItems: snapshot,
                appState: appState
            ) else { return false }
            snapshot = await currentMacOS27ReorderSnapshot(appState: appState)
        }
        guard !Task.isCancelled,
              let currentIce = snapshot.first(matching: .visibleControlItem),
              let currentBoundary = snapshot.first(matching: .nativeBoundary(for: .hidden)),
              MacOS27NativeBoundary.side(of: currentBoundary.bounds, relativeTo: currentIce.bounds) == .left,
              MacOS27NativeBoundary.isImmediatelyBefore(
                currentBoundary.tag,
                currentIce.tag,
                in: snapshot.sorted { $0.bounds.minX < $1.bounds.minX }.map(\.tag)
              )
        else { return false }
        guard updatingCache else { return true }
        let liveItems = snapshot.filter { $0.canBeHidden && !$0.isSystemClone && !$0.isControlItem }
        let refreshed = controller.makeCache(
            liveItems: liveItems,
            sourceItems: snapshot,
            displayID: Bridging.getActiveMenuBarDisplayID()
        )
        if itemCache != refreshed { itemCache = refreshed }
        return true
    }

    @available(macOS 27.0, *)
    private func nativeHidingBoundaryIsReady(on displayID: CGDirectDisplayID) -> Bool {
        let items = MacOS27MenuBarItemProvider.ownMenuBarItems()
        let boundaryTag = MenuBarItemTag.nativeBoundary(for: .hidden)
        guard NSScreen.screens.contains(where: { $0.displayID == displayID }),
              let boundary = items.first(matching: boundaryTag),
              let ice = items.first(matching: .visibleControlItem),
              MacOS27NativeBoundary.canCheckImmediateHide(
                  boundary: boundary.bounds, control: ice.bounds, display: CGDisplayBounds(displayID)
              ) else { return false }
        // This path only resizes our own status item; it sends no input. The
        // system-wide hit map can still describe the previous native layout
        // after our owner geometry has settled, so it must not gate a resize.
        // Actual drag operations continue to verify their input targets.
        let checked = MacOS27MenuBarItemProvider.ownMenuBarItems()
        return checked.first(matching: boundaryTag)?.bounds == boundary.bounds &&
            checked.first(matching: .visibleControlItem)?.bounds == ice.bounds
    }

    /// Caches the current menu bar items, regardless of whether the
    /// items have changed since the previous cache.
    ///
    /// Before caching, this method ensures that the control items for
    /// the hidden and always-hidden sections are correctly ordered,
    /// arranging them into valid positions if needed.
    func cacheItemsRegardless(
        _ currentItemWindowIDs: [CGWindowID]? = nil,
        ignoringRecentMovement: Bool = false,
        refreshingAllOwners: Bool = false
    ) async {
        await cacheActor.runCacheTask { [weak self] in
            guard let self else {
                return
            }

            guard
                ignoringRecentMovement ||
                    !lastMoveOperationOccurred(within: .seconds(1))
            else {
                logger.debug("Skipping menu bar item cache due to recent item movement")
                return
            }

            let displayID = Bridging.getActiveMenuBarDisplayID()
            var items: [MenuBarItem]
            if
                #available(macOS 27.0, *),
                let controller = appState?.menuBarManager.macOS27Controller,
                controller.isLayoutEditing,
                !refreshingAllOwners
            {
                // Refresh only this Layout session's owners while editing instead
                // of rescanning every running process every five seconds. A
                // complete scan can occupy the serialized AX provider for tens
                // of seconds and make a drop look as though it failed.
                // The session keeps zero-item hosts for later republishing;
                // entering the pane still performs one explicit full scan.
                let knownItems = controller.knownItemsForReordering()
                let (sourcePIDs, namespaces) = controller.ownersForLayoutRefresh()
                if sourcePIDs.isEmpty && namespaces.isEmpty {
                    // Settings can restore directly into Layout at launch.
                    items = await MenuBarItem.getMenuBarItems(option: .activeSpace)
                } else {
                    let targetedItems = await Task.detached(priority: .userInitiated) {
                        MacOS27MenuBarItemProvider.menuBarItems(
                            sourcePIDs: sourcePIDs,
                            namespaces: namespaces
                        )
                    }.value
                    items = targetedItems.isEmpty ? knownItems : targetedItems
                }
            } else {
                items = await MenuBarItem.getMenuBarItems(option: .activeSpace)
            }

            guard !Task.isCancelled else { return }
            let itemWindowIDs = currentItemWindowIDs ?? items.reversed().map { $0.windowID }
            await cacheActor.updateCachedItemWindowIDs(itemWindowIDs)
            guard !Task.isCancelled else { return }

            if #available(macOS 27.0, *) {
                let managedItems = items.filter { item in
                    guard item.canBeHidden, !item.isSystemClone else { return false }
                    return !item.isControlItem
                }
                let updatedCache = appState?.menuBarManager.macOS27Controller.makeCache(
                    liveItems: managedItems,
                    sourceItems: items,
                    displayID: displayID
                ) ?? ItemCache(displayID: displayID)
                let cacheToPublish = macOS27DesiredCache ?? macOS27ProjectedCache ?? updatedCache
                if itemCache != cacheToPublish {
                    itemCache = cacheToPublish
                    logger.debug("Updated macOS 27 assignment-backed menu bar item cache")
                }
                appState?.menuBarManager.syncNativeVisibility()
                return
            }

            guard let controlItems = ControlItemPair(items: &items) else {
                // ???: Is clearing the cache the best thing to do here?
                logger.warning("Missing control item for hidden section, clearing menu bar item cache")
                itemCache = ItemCache(displayID: nil)
                return
            }

            await enforceControlItemOrder(controlItems: controlItems)
            await uncheckedCacheItems(items: items, controlItems: controlItems, displayID: displayID)
        }
    }

    /// Caches the current menu bar items, if the items have changed
    /// since the previous cache.
    ///
    /// Before caching, this method ensures that the control items for
    /// the hidden and always-hidden sections are correctly ordered,
    /// arranging them into valid positions if needed.
    func cacheItemsIfNeeded() async {
        if #available(macOS 27.0, *) {
            await cacheItemsRegardless()
            return
        }
        let itemWindowIDs = Bridging.getMenuBarWindowList(option: [.itemsOnly, .activeSpace])
        if await cacheActor.cachedItemWindowIDs != itemWindowIDs {
            await cacheItemsRegardless(itemWindowIDs)
        }
    }
}

// MARK: - Event Helpers

extension MenuBarItemManager {
    /// An error that can occur during menu bar item event operations.
    enum EventError: CustomStringConvertible, LocalizedError {
        /// A generic indication of a failure.
        case cannotComplete
        /// An event source cannot be created or is otherwise invalid.
        case invalidEventSource
        /// The location of the mouse cannot be found.
        case missingMouseLocation
        /// A failure during the creation of an event.
        case eventCreationFailure(MenuBarItem)
        /// A timeout during an event operation.
        case eventOperationTimeout(MenuBarItem)
        /// A menu bar item is not movable.
        case itemNotMovable(MenuBarItem)
        /// A timeout waiting for a menu bar item to respond to an event.
        case itemResponseTimeout(MenuBarItem)
        /// A menu bar item's bounds cannot be found.
        case missingItemBounds(MenuBarItem)

        var description: String {
            switch self {
            case .cannotComplete:
                "\(Self.self).cannotComplete"
            case .invalidEventSource:
                "\(Self.self).invalidEventSource"
            case .missingMouseLocation:
                "\(Self.self).missingMouseLocation"
            case .eventCreationFailure(let item):
                "\(Self.self).eventCreationFailure(item: \(item.tag))"
            case .eventOperationTimeout(let item):
                "\(Self.self).eventOperationTimeout(item: \(item.tag))"
            case .itemNotMovable(let item):
                "\(Self.self).itemNotMovable(item: \(item.tag))"
            case .itemResponseTimeout(let item):
                "\(Self.self).itemResponseTimeout(item: \(item.tag))"
            case .missingItemBounds(let item):
                "\(Self.self).missingItemBounds(item: \(item.tag))"
            }
        }

        var errorDescription: String? {
            switch self {
            case .cannotComplete:
                "Operation could not be completed"
            case .invalidEventSource:
                "Invalid event source"
            case .missingMouseLocation:
                "Missing mouse location"
            case .eventCreationFailure(let item):
                "Could not create event for \"\(item.displayName)\""
            case .eventOperationTimeout(let item):
                "Event operation timed out for \"\(item.displayName)\""
            case .itemNotMovable(let item):
                "\"\(item.displayName)\" is not movable"
            case .itemResponseTimeout(let item):
                "\"\(item.displayName)\" took too long to respond"
            case .missingItemBounds(let item):
                "Missing bounds rectangle for \"\(item.displayName)\""
            }
        }

        var recoverySuggestion: String? {
            if case .itemNotMovable = self { return nil }
            return "Please try again. If the error persists, please file a bug report."
        }
    }

    /// Returns a Boolean value that indicates whether the user has
    /// paused input for at least the given duration.
    ///
    /// - Parameter duration: The duration that certain types of input
    ///   events must not have occured within in order to return `true`.
    private nonisolated func hasUserPausedInput(for duration: Duration) -> Bool {
        NSEvent.modifierFlags.isEmpty &&
        !MouseHelpers.lastMovementOccurred(within: duration) &&
        !MouseHelpers.lastScrollWheelOccurred(within: duration) &&
        !MouseHelpers.isButtonPressed()
    }

    /// Waits asynchronously for the user to pause input.
    private nonisolated func waitForUserToPauseInput() async throws {
        let waitTask = Task {
            while true {
                try Task.checkCancellation()
                if hasUserPausedInput(for: .milliseconds(50)) {
                    break
                }
                try await Task.sleep(for: .milliseconds(250))
            }
        }
        do {
            try await waitTask.value
        } catch {
            throw EventError.cannotComplete
        }
    }

    /// Waits between move operations for a dynamic amount of time,
    /// based on the timestamp of the last move operation.
    private nonisolated func waitForMoveOperationBuffer() async throws {
        if let timestamp = await lastMoveOperationTimestamp {
            let buffer = max(.milliseconds(25) - timestamp.duration(to: .now), .zero)
            logger.debug("Move operation buffer: \(buffer)")
            do {
                try await Task.sleep(for: buffer)
            } catch {
                throw EventError.cannotComplete
            }
        }
    }

    /// Waits for the given duration between event operations.
    ///
    /// Since most event operations must perform cleanup or otherwise
    /// run to completion, this method ignores task cancellation.
    private nonisolated func eventSleep(for duration: Duration = .milliseconds(25)) async {
        let task = Task {
            try? await Task.sleep(for: duration)
        }
        await task.value
    }

    /// Returns the current bounds for the given item.
    private nonisolated func getCurrentBounds(for item: MenuBarItem) async throws -> CGRect {
        if #available(macOS 27.0, *) {
            let items = await MenuBarItem.getMenuBarItems(option: .activeSpace)
            return items.first(where: { $0.tag == item.tag })?.bounds ?? item.bounds
        }
        let task = Task.detached(priority: .userInitiated) {
            guard let bounds = Bridging.getWindowBounds(for: item.windowID) else {
                throw EventError.missingItemBounds(item)
            }
            return bounds
        }
        return try await task.value
    }

    /// Returns the current mouse location.
    private nonisolated func getMouseLocation() throws -> CGPoint {
        guard let location = MouseHelpers.locationCoreGraphics else {
            throw EventError.missingMouseLocation
        }
        return location
    }

    /// Returns the process identifier that can be used to create
    /// and post a menu bar item event.
    private nonisolated func getEventPID(for item: MenuBarItem) -> pid_t {
        item.sourcePID ?? item.ownerPID
    }

    /// Returns an event source for a menu bar item event operation.
    private nonisolated func getEventSource(
        with stateID: CGEventSourceStateID = .hidSystemState
    ) throws -> CGEventSource {
        enum Context {
            static var cache = [CGEventSourceStateID: CGEventSource]()
        }
        if let source = Context.cache[stateID] {
            return source
        }
        guard let source = CGEventSource(stateID: stateID) else {
            throw EventError.invalidEventSource
        }
        Context.cache[stateID] = source
        return source
    }

    /// Prevents local events from being suppressed.
    private nonisolated func permitLocalEvents() throws {
        let source = try getEventSource(with: .combinedSessionState)
        let states: [CGEventSuppressionState] = [
            .eventSuppressionStateRemoteMouseDrag,
            .eventSuppressionStateSuppressionInterval,
        ]
        for state in states {
            source.setLocalEventsFilterDuringSuppressionState(.permitAllEvents, state: state)
        }
        source.localEventsSuppressionInterval = 0
    }

    /// Posts an event to the given menu bar item and waits until
    /// it is received before returning.
    ///
    /// - Parameters:
    ///   - event: The event to post.
    ///   - item: The menu bar item that the event targets.
    ///   - timeout: The base duration to wait before throwing an error.
    ///     The value of this parameter is multiplied by `count` to
    ///     produce the actual timeout duration.
    ///   - count: The number of times to repeat the operation. As it
    ///     is considerably more efficient, prefer increasing this value
    ///     over repeatedly calling `postEventWithBarrier`.
    private nonisolated func postEventWithBarrier(
        _ event: CGEvent,
        to item: MenuBarItem,
        timeout: Duration,
        repeating count: Int = 1
    ) async throws {
        MouseHelpers.hideCursor()
        defer {
            MouseHelpers.showCursor()
        }

        guard
            let entryEvent = CGEvent.uniqueNullEvent(),
            let exitEvent = CGEvent.uniqueNullEvent()
        else {
            throw EventError.eventCreationFailure(item)
        }

        let pid = getEventPID(for: item)
        event.setTargetPID(pid)

        let firstLocation = EventTap.Location.pid(pid)
        let secondLocation = EventTap.Location.sessionEventTap

        var count = count
        var eventTaps = [EventTap]()

        let timeoutTask = Task(timeout: timeout * count) {
            try await withCheckedThrowingContinuation { continuation in
                // Listen for the following events at the first location
                // and perform the following actions:
                //
                // - Entry event: Decrement the count and post the real
                //   event to the second location (handled in EventTap 2).
                // - Exit event: Resume the continuation.
                //
                // These events serve as start (or continue) and stop
                // signals, and are discarded.
                let eventTap1 = EventTap(
                    label: "EventTap 1",
                    type: .null,
                    location: firstLocation,
                    placement: .headInsertEventTap,
                    option: .defaultTap
                ) { tap, rEvent in
                    if rEvent.matches(entryEvent, byIntegerFields: [.eventSourceUserData]) {
                        count -= 1
                        event.post(to: secondLocation)
                        return nil
                    }
                    if rEvent.matches(exitEvent, byIntegerFields: [.eventSourceUserData]) {
                        tap.disable()
                        continuation.resume()
                        return nil
                    }
                    return rEvent
                }

                // Listen for the real event at the second location and,
                // depending on the count, post either the entry or exit
                // event to the first location (handled in EventTap 1).
                let eventTap2 = EventTap(
                    label: "EventTap 2",
                    type: event.type,
                    location: secondLocation,
                    placement: .tailAppendEventTap,
                    option: .listenOnly
                ) { tap, rEvent in
                    guard rEvent.matches(event, byIntegerFields: CGEventField.menuBarItemEventFields) else {
                        return rEvent
                    }
                    if count <= 0 {
                        tap.disable()
                        exitEvent.post(to: firstLocation)
                    } else {
                        entryEvent.post(to: firstLocation)
                    }
                    rEvent.setTargetPID(pid)
                    return rEvent
                }

                // Keep the taps alive.
                eventTaps.append(eventTap1)
                eventTaps.append(eventTap2)

                Task {
                    await withTaskCancellationHandler {
                        eventTap1.enable()
                        eventTap2.enable()
                        entryEvent.post(to: firstLocation)
                    } onCancel: {
                        eventTap1.disable()
                        eventTap2.disable()
                        continuation.resume(throwing: CancellationError())
                    }
                }
            }
        }
        do {
            try await timeoutTask.value
        } catch is TaskTimeoutError {
            throw EventError.eventOperationTimeout(item)
        } catch {
            throw EventError.cannotComplete
        }
    }

    /// Casts forbidden magic to make a menu bar item receive and
    /// respond to an event during a move operation.
    ///
    /// - Parameters:
    ///   - event: The event to post.
    ///   - item: The menu bar item that the event targets.
    ///   - timeout: The base duration to wait before throwing an error.
    ///     The value of this parameter is multiplied by `count` to
    ///     produce the actual timeout duration.
    ///   - count: The number of times to repeat the operation. As it
    ///     is considerably more efficient, prefer increasing this value
    ///     over repeatedly calling `scrombleEvent`.
    private nonisolated func scrombleEvent(
        _ event: CGEvent,
        item: MenuBarItem,
        timeout: Duration,
        repeating count: Int = 1
    ) async throws {
        MouseHelpers.hideCursor()
        defer {
            MouseHelpers.showCursor()
        }

        guard
            let entryEvent = CGEvent.uniqueNullEvent(),
            let exitEvent = CGEvent.uniqueNullEvent()
        else {
            throw EventError.eventCreationFailure(item)
        }

        let pid = getEventPID(for: item)
        event.setTargetPID(pid)

        let firstLocation = EventTap.Location.pid(pid)
        let secondLocation = EventTap.Location.sessionEventTap

        var count = count
        var eventTaps = [EventTap]()

        let timeoutTask = Task(timeout: timeout * count) {
            try await withCheckedThrowingContinuation { continuation in
                // Listen for the following events at the first location
                // and perform the following actions:
                //
                // - Entry event: Decrement the count and post the real
                //   event to the second location (handled in EventTap 2).
                // - Exit event: Resume the continuation.
                //
                // These events serve as start (or continue) and stop
                // signals, and are discarded.
                let eventTap1 = EventTap(
                    label: "EventTap 1",
                    type: .null,
                    location: firstLocation,
                    placement: .headInsertEventTap,
                    option: .defaultTap
                ) { tap, rEvent in
                    if rEvent.matches(entryEvent, byIntegerFields: [.eventSourceUserData]) {
                        count -= 1
                        event.post(to: secondLocation)
                        return nil
                    }
                    if rEvent.matches(exitEvent, byIntegerFields: [.eventSourceUserData]) {
                        tap.disable()
                        continuation.resume()
                        return nil
                    }
                    return rEvent
                }

                // Listen for the real event at the second location and
                // post the real event to the first location (handled in
                // EventTap 3).
                let eventTap2 = EventTap(
                    label: "EventTap 2",
                    type: event.type,
                    location: secondLocation,
                    placement: .tailAppendEventTap,
                    option: .listenOnly
                ) { tap, rEvent in
                    guard rEvent.matches(event, byIntegerFields: CGEventField.menuBarItemEventFields) else {
                        return rEvent
                    }
                    if count <= 0 {
                        tap.disable()
                    }
                    event.post(to: firstLocation)
                    rEvent.setTargetPID(pid)
                    return rEvent
                }

                // Listen for the real event at the first location and,
                // depending on the count, post either the entry or exit
                // event to the first location (handled in EventTap 1).
                let eventTap3 = EventTap(
                    label: "EventTap 3",
                    type: event.type,
                    location: firstLocation,
                    placement: .headInsertEventTap,
                    option: .listenOnly
                ) { tap, rEvent in
                    guard rEvent.matches(event, byIntegerFields: CGEventField.menuBarItemEventFields) else {
                        return rEvent
                    }
                    if count <= 0 {
                        tap.disable()
                        exitEvent.post(to: firstLocation)
                    } else {
                        entryEvent.post(to: firstLocation)
                    }
                    rEvent.setTargetPID(pid)
                    return rEvent
                }

                // Keep the taps alive.
                eventTaps.append(eventTap1)
                eventTaps.append(eventTap2)
                eventTaps.append(eventTap3)

                Task {
                    await withTaskCancellationHandler {
                        eventTap1.enable()
                        eventTap2.enable()
                        eventTap3.enable()
                        entryEvent.post(to: firstLocation)
                    } onCancel: {
                        eventTap1.disable()
                        eventTap2.disable()
                        eventTap3.disable()
                        continuation.resume(throwing: CancellationError())
                    }
                }
            }
        }
        do {
            try await timeoutTask.value
        } catch is TaskTimeoutError {
            throw EventError.eventOperationTimeout(item)
        } catch {
            throw EventError.cannotComplete
        }
    }
}

// MARK: - Moving Items

extension MenuBarItemManager {
    /// Destinations for menu bar item move operations.
    enum MoveDestination {
        /// The destination to the left of the given target item.
        case leftOfItem(MenuBarItem)
        /// The destination to the right of the given target item.
        case rightOfItem(MenuBarItem)

        /// The destination's target item.
        var targetItem: MenuBarItem {
            switch self {
            case .leftOfItem(let item), .rightOfItem(let item): item
            }
        }

        /// A string to use for logging purposes.
        var logString: String {
            switch self {
            case .leftOfItem(let item): "left of \(item.logString)"
            case .rightOfItem(let item): "right of \(item.logString)"
            }
        }
    }

    /// Returns the default timeout for move operations associated
    /// with the given item.
    private func getDefaultMoveOperationTimeout(for item: MenuBarItem) -> Duration {
        if item.isBentoBox {
            // Bento Boxes (i.e. Control Center groups) generally
            // take a little longer to respond.
            return .milliseconds(100)
        }
        return .milliseconds(50)
    }

    /// Returns the cached timeout for move operations associated
    /// with the given item.
    private func getMoveOperationTimeout(for item: MenuBarItem) -> Duration {
        if let timeout = moveOperationTimeouts[item.tag] {
            return timeout
        }
        return getDefaultMoveOperationTimeout(for: item)
    }

    /// Updates the cached timeout for move operations associated
    /// with the given item.
    private func updateMoveOperationTimeout(_ timeout: Duration, for item: MenuBarItem) {
        let current = getMoveOperationTimeout(for: item)
        let average = (timeout + current) / 2
        let clamped = average.clamped(min: .milliseconds(25), max: .milliseconds(150))
        moveOperationTimeouts[item.tag] = clamped
    }

    /// Returns the target points for creating the events needed to
    /// move a menu bar item to the given destination.
    private nonisolated func getTargetPoints(
        forMoving item: MenuBarItem,
        to destination: MoveDestination
    ) async throws -> (start: CGPoint, end: CGPoint) {
        let itemBounds = try await getCurrentBounds(for: item)
        let targetBounds = try await getCurrentBounds(for: destination.targetItem)
        switch destination {
        case .leftOfItem:
            var start = CGPoint(x: targetBounds.minX, y: targetBounds.minY)
            var end = start
            if itemBounds.maxX <= targetBounds.minX {
                // Direction of movement: ->
                end.x -= itemBounds.width
            } else {
                // Direction of movement: <-
                start.x -= 1
            }
            return (start, end)
        case .rightOfItem:
            var start = CGPoint(x: targetBounds.maxX, y: targetBounds.minY)
            var end = start
            if itemBounds.minX <= targetBounds.maxX {
                // Direction of movement: ->
                end.x -= itemBounds.width
            } else {
                // Direction of movement: <-
                start.x += 1
            }
            return (start, end)
        }
    }

    /// Returns a Boolean value that indicates whether the given menu bar
    /// item has the correct position, relative to the given destination.
    private nonisolated func itemHasCorrectPosition(
        item: MenuBarItem,
        for destination: MoveDestination
    ) async throws -> Bool {
        let itemBounds = try await getCurrentBounds(for: item)
        let targetBounds = try await getCurrentBounds(for: destination.targetItem)
        return switch destination {
        case .leftOfItem: itemBounds.maxX == targetBounds.minX
        case .rightOfItem: itemBounds.minX == targetBounds.maxX
        }
    }

    /// Checks a hosted macOS 27 menu bar move using a supplied targeted AX
    /// snapshot. Comparing ordinal adjacency avoids another full menu-bar walk.
    @available(macOS 27.0, *)
    private nonisolated func macOS27ItemHasCorrectPosition(
        item: MenuBarItem,
        for destination: MoveDestination,
        among snapshot: [MenuBarItem],
        requiredSection: MenuBarSection.Name? = nil
    ) -> Bool {
        let items = snapshot.sorted { $0.bounds.minX < $1.bounds.minX }

        func index(of needle: MenuBarItem) -> Int? {
            items.firstIndex { $0.windowID == needle.windowID }
                ?? items.firstIndex(matching: needle.tag)
        }

        guard
            let itemIndex = index(of: item),
            let targetIndex = index(of: destination.targetItem)
        else {
            return false
        }
        let hasRequestedAdjacency = switch destination {
        case .leftOfItem: itemIndex == targetIndex - 1
        case .rightOfItem: itemIndex == targetIndex + 1
        }
        guard hasRequestedAdjacency, let requiredSection else {
            return hasRequestedAdjacency
        }

        // A cross-section Layout drop is complete only after the item is on
        // the requested side of Ice. Relative adjacency alone can already be
        // true in a stale hosted snapshot while both items are still on the
        // opposite side of the section boundary.
        guard let iceIndex = items.firstIndex(matching: .nativeBoundary(for: requiredSection)) else {
            return false
        }
        return switch requiredSection {
        case .visible: itemIndex > iceIndex
        case .hidden, .alwaysHidden: itemIndex < iceIndex
        }
    }

    /// Refreshes every owner in the transaction snapshot so long-move
    /// verification observes the complete physical permutation.
    @available(macOS 27.0, *)
    private nonisolated func targetedMacOS27Items(
        item: MenuBarItem,
        destination: MoveDestination,
        contextItems: [MenuBarItem],
        additionallyRequiring additionalTags: Set<MenuBarItemTag> = []
    ) async -> [MenuBarItem] {
        let target = destination.targetItem
        let ordered = contextItems.sorted { $0.bounds.minX < $1.bounds.minX }
        var relevantItems = [item, target]

        if
            let itemIndex = ordered.firstIndex(matching: item.tag),
            let targetIndex = ordered.firstIndex(matching: target.tag)
        {
            let lowerBound = min(itemIndex, targetIndex)
            let upperBound = max(itemIndex, targetIndex)
            relevantItems.append(contentsOf: ordered[lowerBound ... upperBound])

            // Include the item beyond the requested insertion edge. Without
            // it, an overshoot could look like valid adjacency in a targeted
            // snapshot that omitted the intervening owner.
            let withoutMovedItem = ordered.filter { $0.tag != item.tag }
            if let refreshedTargetIndex = withoutMovedItem.firstIndex(matching: target.tag) {
                let farIndex: Int? = switch destination {
                case .leftOfItem:
                    refreshedTargetIndex > withoutMovedItem.startIndex
                        ? refreshedTargetIndex - 1
                        : nil
                case .rightOfItem:
                    refreshedTargetIndex + 1 < withoutMovedItem.endIndex
                        ? refreshedTargetIndex + 1
                        : nil
                }
                if let farIndex {
                    relevantItems.append(withoutMovedItem[farIndex])
                }
            }
        }
        relevantItems.append(contentsOf: ordered.filter { additionalTags.contains($0.tag) })

        let sourcePIDs = Set(relevantItems.map {
            $0.sourcePID ?? $0.ownerPID
        })
        let namespaces = Set(relevantItems.map(\.tag.namespace))
        return await Task.detached(priority: .userInitiated) {
            MacOS27MenuBarItemProvider.menuBarItems(
                sourcePIDs: sourcePIDs,
                namespaces: namespaces
            )
        }.value
    }

    /// Refreshes the physical range touched by a user-initiated move and merges
    /// it into the controller's complete snapshot. Rewalking every known owner
    /// before every drag made a two-icon move wait on unrelated applications.
    /// The affected range plus its far-edge guard is sufficient for the native
    /// adjacent-swap transaction; a full walk remains the endpoint fallback.
    @available(macOS 27.0, *)
    private nonisolated func currentMacOS27Items(
        knownItems: [MenuBarItem],
        item: MenuBarItem,
        destination: MoveDestination,
        requiring requiredTags: Set<MenuBarItemTag>
    ) async -> [MenuBarItem] {
        let targeted = await targetedMacOS27Items(
            item: item,
            destination: destination,
            contextItems: knownItems,
            additionallyRequiring: requiredTags
        )
        let targetedTags = Set(targeted.map(\.tag))
        if requiredTags.isSubset(of: targetedTags) {
            return Array(
                Dictionary(
                    (knownItems + targeted).map { ($0.tag, $0) },
                    uniquingKeysWith: { _, refreshed in refreshed }
                ).values
            )
        }

        // A just-launched owner may not have reached the controller snapshot
        // yet. Fall back to one complete walk only when a required endpoint is
        // genuinely absent from the fast path.
        return await Task.detached(priority: .userInitiated) {
            MacOS27MenuBarItemProvider.menuBarItems(on: nil, option: .activeSpace)
        }.value
    }

    /// Posts the native Command-drag that MenuBarAgent uses for macOS 27
    /// status-item reordering, for Layout or alignment of Ice's own boundary.
    @available(macOS 27.0, *)
    private nonisolated func postMacOS27CommandDrag(
        item: MenuBarItem,
        destination: MoveDestination
    ) async throws {
        try Task.checkCancellation()
        let itemBounds = item.bounds
        let targetBounds = destination.targetItem.bounds
        let start = itemBounds.center
        let endX = switch destination {
        case .leftOfItem: targetBounds.minX - 3
        case .rightOfItem: targetBounds.maxX + 3
        }
        let end = CGPoint(
            x: endX,
            y: targetBounds.midY
        )
        let originalMouseLocation = try getMouseLocation()
        let source = try getEventSource(with: .combinedSessionState)
        try permitLocalEvents()

        guard
            let commandDown = CGEvent(
                keyboardEventSource: source,
                virtualKey: 0x37,
                keyDown: true
            ),
            let commandUp = CGEvent(
                keyboardEventSource: source,
                virtualKey: 0x37,
                keyDown: false
            )
        else {
            throw EventError.eventCreationFailure(item)
        }
        commandDown.flags = .maskCommand
        var commandIsDown = false
        var mouseIsDown = false

        func event(_ type: CGEventType, at point: CGPoint) throws -> CGEvent {
            guard let event = CGEvent(
                mouseEventSource: source,
                mouseType: type,
                mouseCursorPosition: point,
                mouseButton: .left
            ) else {
                throw EventError.eventCreationFailure(item)
            }
            // Long moves need one non-coalesced sample for every crossed
            // insertion boundary so crossing several neighbors is one drag.
            event.flags = [.maskCommand, .maskNonCoalesced]
            return event
        }

        let mouseUp = try event(.leftMouseUp, at: end)
        MouseHelpers.hideCursor()
        defer {
            if mouseIsDown { mouseUp.post(tap: .cghidEventTap) }
            if commandIsDown {
                commandUp.post(tap: .cghidEventTap)
            }
            MouseHelpers.warpCursor(to: originalMouseLocation)
            MouseHelpers.showCursor()
        }

        MouseHelpers.warpCursor(to: start)
        commandDown.post(tap: .cghidEventTap)
        commandIsDown = true
        await eventSleep(for: .milliseconds(24))
        // Before mouse-down a cancelled request can still stop safely. Once
        // pressed, finish the drag and release both inputs before unpinning.
        try Task.checkCancellation()
        try event(.leftMouseDown, at: start).post(tap: .cghidEventTap)
        mouseIsDown = true
        await eventSleep(for: .milliseconds(55))

        let distance = abs(end.x - start.x)
        let steps = max(12, min(42, Int(ceil(distance / 6))))
        for index in 1 ... steps {
            let progress = CGFloat(index) / CGFloat(steps)
            let point = CGPoint(
                x: start.x + (end.x - start.x) * progress,
                y: start.y + (end.y - start.y) * progress
            )
            try event(.leftMouseDragged, at: point).post(tap: .cghidEventTap)
            await eventSleep(for: .milliseconds(5))
        }
        await eventSleep(for: .milliseconds(28))
        mouseUp.post(tap: .cghidEventTap)
        mouseIsDown = false
        commandUp.post(tap: .cghidEventTap)
        commandIsDown = false
    }

    /// Layout sends a native drag, then observes the actual settled result.
    /// Never rewrite preference guesses or freeze the system compositor.
    @available(macOS 27.0, *)
    private func performMacOS27NativeMove(
        item: MenuBarItem,
        destination: MoveDestination,
        contextItems: [MenuBarItem],
        appState: AppState,
        requiredSection: MenuBarSection.Name? = nil
    ) async -> Bool {
        let isOwnBoundaryAlignment: Bool
        if case .leftOfItem(let target) = destination {
            isOwnBoundaryAlignment = item.tag == .nativeBoundary(for: .hidden) && target.tag == .visibleControlItem
        } else {
            isOwnBoundaryAlignment = false
        }
        guard appState.menuBarManager.macOS27Controller.isLayoutEditing || isOwnBoundaryAlignment else { return false }
        do {
            try await eventSemaphore.waitUnlessCancelled()
        } catch {
            return false
        }
        defer { eventSemaphore.signal() }

        var snapshot = contextItems
        for _ in 0 ..< 2 {
            guard !Task.isCancelled,
                  let liveItem = snapshot.first(matching: item.tag),
                  let liveTarget = snapshot.first(matching: destination.targetItem.tag)
            else { return false }
            guard NSScreen.screens.contains(where: {
                MacOS27NativeBoundary.canDrag(
                    from: liveItem.bounds, to: liveTarget.bounds, on: CGDisplayBounds($0.displayID)
                )
            }) else { return false }
            if isOwnBoundaryAlignment {
                let hitIdentifier = AXHelpers.element(at: liveItem.bounds.center)
                    .flatMap { AXHelpers.identifier(for: $0) }
                guard hitIdentifier == liveItem.tag.title else {
                    logger.error("Refusing boundary drag: hit target \(hitIdentifier ?? "none", privacy: .public) does not match Ice's boundary at \(liveItem.bounds.debugDescription, privacy: .public)")
                    return false
                }
            }
            let requested: MoveDestination = switch destination {
            case .leftOfItem: .leftOfItem(liveTarget)
            case .rightOfItem: .rightOfItem(liveTarget)
            }
            do {
                appState.menuBarManager.beginNativeDrag()
                defer { appState.menuBarManager.endNativeDrag() }
                lastMoveOperationTimestamp = .now
                try await postMacOS27CommandDrag(item: liveItem, destination: requested)
                lastMoveOperationTimestamp = .now
            } catch is CancellationError {
                return false
            } catch {
                logger.error("Native Layout drag failed: \(error, privacy: .public)")
                return false
            }

            var verifiedSamples = 0
            for _ in 0 ..< 12 {
                try? await Task.sleep(for: .milliseconds(80))
                guard !Task.isCancelled else { return false }
                snapshot = await currentMacOS27ReorderSnapshot(appState: appState)
                guard let moved = snapshot.first(matching: item.tag),
                      let target = snapshot.first(matching: destination.targetItem.tag)
                else { continue }
                let refreshed: MoveDestination = switch destination {
                case .leftOfItem: .leftOfItem(target)
                case .rightOfItem: .rightOfItem(target)
                }
                if macOS27ItemHasCorrectPosition(
                    item: moved,
                    for: refreshed,
                    among: snapshot,
                    requiredSection: requiredSection
                ) {
                    verifiedSamples += 1
                    if verifiedSamples == 2 { return true }
                } else {
                    verifiedSamples = 0
                }
            }
        }
        return false
    }

    /// Waits for a menu bar item to respond to a series of previously
    /// posted move events.
    ///
    /// - Parameters:
    ///   - item: The item to check for a response.
    ///   - initialOrigin: The origin of the item before the events were posted.
    ///   - timeout: The duration to wait before throwing an error.
    private nonisolated func waitForMoveEventResponse(
        from item: MenuBarItem,
        initialOrigin: CGPoint,
        timeout: Duration
    ) async throws -> CGPoint {
        MouseHelpers.hideCursor()
        defer {
            MouseHelpers.showCursor()
        }
        let responseTask = Task.detached {
            while true {
                try Task.checkCancellation()
                let origin = try await self.getCurrentBounds(for: item).origin
                if origin != initialOrigin {
                    return origin
                }
                // Give the target application time to process the move and,
                // on macOS 27, avoid hammering the serialized AX item scan.
                try await Task.sleep(for: .milliseconds(10))
            }
        }
        let timeoutTask = Task(timeout: timeout) {
            try await withTaskCancellationHandler {
                try await responseTask.value
            } onCancel: {
                responseTask.cancel()
            }
        }
        do {
            let origin = try await timeoutTask.value
            logger.debug(
                """
                Item responded to events with new origin: \
                \(String(describing: origin), privacy: .public)
                """
            )
            return origin
        } catch let error as EventError {
            throw error
        } catch is TaskTimeoutError {
            throw EventError.itemResponseTimeout(item)
        } catch {
            throw EventError.cannotComplete
        }
    }

    /// Creates and posts a series of events to move a menu bar item
    /// to the given destination.
    ///
    /// - Parameters:
    ///   - item: The menu bar item to move.
    ///   - destination: The destination to move the menu bar item.
    private func postMoveEvents(
        item: MenuBarItem,
        destination: MoveDestination,
        hostedByMenuBarAgent: Bool = false
    ) async throws {
        try await eventSemaphore.waitUnlessCancelled()
        defer {
            eventSemaphore.signal()
        }

        var itemOrigin = try await getCurrentBounds(for: item).origin
        let targetPoints: (start: CGPoint, end: CGPoint)
        if hostedByMenuBarAgent {
            let targetBounds = try await getCurrentBounds(for: destination.targetItem)
            // macOS 27's hosted status items respond to a press/release at the
            // destination edge with the moved item's window ID stamped on the
            // press. A conventional drag gesture is ignored by MenuBarAgent.
            let point = switch destination {
            case .leftOfItem: CGPoint(x: targetBounds.minX, y: targetBounds.minY)
            case .rightOfItem: CGPoint(x: targetBounds.maxX, y: targetBounds.minY)
            }
            targetPoints = (point, point)
        } else {
            targetPoints = try await getTargetPoints(forMoving: item, to: destination)
        }
        let mouseLocation = try getMouseLocation()
        let source = try getEventSource()

        try permitLocalEvents()

        guard
            let mouseDown = CGEvent.menuBarItemEvent(
                item: item,
                source: source,
                type: .move(.mouseDown),
                location: targetPoints.start
            ),
            let mouseUp = CGEvent.menuBarItemEvent(
                item: destination.targetItem,
                source: source,
                type: .move(.mouseUp),
                location: targetPoints.end
            )
        else {
            throw EventError.eventCreationFailure(item)
        }

        var timeout = getMoveOperationTimeout(for: item)
        if hostedByMenuBarAgent {
            // Hosted items need noticeably longer than legacy WindowServer
            // items when MenuBarAgent is recomposing the bar.
            timeout = max(timeout, .milliseconds(350))
            MouseHelpers.warpCursor(to: targetPoints.start)
            await eventSleep(for: .milliseconds(20))
        }
        logger.debug("Move operation timeout: \(timeout)")

        lastMoveOperationTimestamp = .now
        MouseHelpers.hideCursor()
        defer {
            MouseHelpers.warpCursor(to: mouseLocation)
            MouseHelpers.showCursor()
            lastMoveOperationTimestamp = .now
            updateMoveOperationTimeout(timeout, for: item)
        }

        do {
            try await scrombleEvent(
                mouseDown,
                item: item,
                timeout: timeout
            )
            itemOrigin = try await waitForMoveEventResponse(
                from: item,
                initialOrigin: itemOrigin,
                timeout: timeout
            )
            try await scrombleEvent(
                mouseUp,
                item: item,
                timeout: timeout,
                repeating: 2 // Double mouse up prevents invalid item state.
            )
            itemOrigin = try await waitForMoveEventResponse(
                from: item,
                initialOrigin: itemOrigin,
                timeout: timeout
            )
            timeout -= timeout / 4
        } catch {
            do {
                logger.warning("Move events failed, posting fallback")
                try await scrombleEvent(
                    mouseUp,
                    item: item,
                    timeout: .milliseconds(100), // Fixed timeout for fallback.
                    repeating: 2 // Double mouse up prevents invalid item state.
                )
            } catch {
                // Catch this for logging purposes only. We want to propagate
                // the original error.
                logger.error("Fallback failed with error: \(error, privacy: .public)")
            }
            timeout += timeout / 2
            throw error
        }
    }

    @available(macOS 27.0, *)
    private struct MacOS27MoveInstruction {
        let item: MenuBarItem
        let destination: MoveDestination
        let requiredSection: MenuBarSection.Name
    }

    @available(macOS 27.0, *)
    private enum MacOS27DesiredOrderStatus {
        case converged
        case incomplete
        case needsMove(MenuBarItemTag)
    }

    @available(macOS 27.0, *)
    private enum MacOS27ReorderError: Error {
        case endpointUnavailable
    }

    /// Records one Layout edit in the desired cache and returns immediately.
    /// The shared worker consumes only the newest complete order.
    @available(macOS 27.0, *)
    private func enqueueMacOS27Move(
        item: MenuBarItem,
        to destination: MoveDestination,
        requiredSection: MenuBarSection.Name?
    ) {
        let previousDesired = macOS27DesiredCache ?? itemCache
        var desired = previousDesired
        for section in MenuBarSection.Name.allCases {
            desired[section].removeAll { $0.tag == item.tag }
        }
        desired.insert(item, at: destination)

        // A cross-section AppKit drop already knows its destination container.
        // If its neighbor vanished between the drop and this run-loop turn,
        // preserve the section request instead of silently reinserting the item
        // into the target's stale section.
        if
            let requiredSection,
            desired.address(for: item.tag)?.section != requiredSection
        {
            for section in MenuBarSection.Name.allCases {
                desired[section].removeAll { $0.tag == item.tag }
            }
            if requiredSection == .visible {
                desired[requiredSection].insert(item, at: 0)
            } else {
                desired[requiredSection].append(item)
            }
        }

        var touchedTags = macOS27ChangedTags(from: previousDesired, to: desired)
        touchedTags.formUnion([item.tag, destination.targetItem.tag])
        enqueueMacOS27DesiredCache(
            desired,
            sourceTag: item.tag,
            touchedTags: touchedTags
        )
    }

    /// Records a move into an otherwise empty Layout section.
    @available(macOS 27.0, *)
    private func enqueueMacOS27Move(
        item: MenuBarItem,
        toSection section: MenuBarSection.Name
    ) {
        let previousDesired = macOS27DesiredCache ?? itemCache
        var desired = previousDesired
        for existingSection in MenuBarSection.Name.allCases {
            desired[existingSection].removeAll { $0.tag == item.tag }
        }
        if section == .visible {
            desired[section].insert(item, at: 0)
        } else {
            desired[section].append(item)
        }
        var touchedTags = macOS27ChangedTags(from: previousDesired, to: desired)
        touchedTags.insert(item.tag)
        enqueueMacOS27DesiredCache(
            desired,
            sourceTag: item.tag,
            touchedTags: touchedTags
        )
    }

    @available(macOS 27.0, *)
    private func macOS27ChangedTags(
        from oldCache: ItemCache,
        to newCache: ItemCache
    ) -> Set<MenuBarItemTag> {
        let tags = Set((oldCache.managedItems + newCache.managedItems).map(\.tag))
        return Set(tags.filter { tag in
            let oldAddress = oldCache.address(for: tag)
            let newAddress = newCache.address(for: tag)
            return oldAddress?.section != newAddress?.section ||
                oldAddress?.index != newAddress?.index
        })
    }

    @available(macOS 27.0, *)
    private func enqueueMacOS27DesiredCache(
        _ desired: ItemCache,
        sourceTag: MenuBarItemTag,
        touchedTags: Set<MenuBarItemTag>
    ) {
        macOS27DesiredGeneration &+= 1
        let generation = macOS27DesiredGeneration
        macOS27DesiredCache = desired
        macOS27TouchedMoveTags.formUnion(touchedTags)
        appState?.menuBarManager.macOS27Controller.beginReordering()
        macOS27PendingMoveGenerations[sourceTag] = generation
        macOS27PendingMoveOrder.removeAll { $0 == sourceTag }
        macOS27PendingMoveOrder.append(sourceTag)

        // This is the editor preview, not an animation. It remains the only
        // order Layout publishes until the real menu bar has converged.
        if itemCache != desired {
            itemCache = desired
        }

        logger.debug("Queued macOS 27 desired menu bar order generation \(generation, privacy: .public)")
        startMacOS27ReorderWorkerIfNeeded()
    }

    @available(macOS 27.0, *)
    private func startMacOS27ReorderWorkerIfNeeded() {
        guard macOS27ReorderTask == nil else { return }
        macOS27ReorderTask = Task { @MainActor [weak self] in
            await self?.runMacOS27ReorderWorker()
        }
    }

    /// Waits for a short input quiet period. A single drag still begins quickly,
    /// while several drops in the same gesture burst become one final order.
    @available(macOS 27.0, *)
    private func waitForMacOS27DesiredOrderToSettle() async -> Bool {
        while !Task.isCancelled {
            let generation = macOS27DesiredGeneration
            do {
                try await Task.sleep(for: .milliseconds(180))
            } catch {
                return false
            }
            if generation == macOS27DesiredGeneration {
                return true
            }
        }
        return false
    }

    @available(macOS 27.0, *)
    private func macOS27MoveInstruction(
        for tag: MenuBarItemTag,
        desiredCache: ItemCache,
        appState: AppState
    ) -> MacOS27MoveInstruction? {
        guard let address = desiredCache.address(for: tag) else { return nil }
        let items = desiredCache[address.section]
        guard items.indices.contains(address.index) else { return nil }
        let item = items[address.index]

        if items.indices.contains(address.index + 1) {
            return MacOS27MoveInstruction(
                item: item,
                destination: .leftOfItem(items[address.index + 1]),
                requiredSection: address.section
            )
        }
        if items.indices.contains(address.index - 1) {
            return MacOS27MoveInstruction(
                item: item,
                destination: .rightOfItem(items[address.index - 1]),
                requiredSection: address.section
            )
        }

        guard
            let iceItem = appState.menuBarManager.macOS27Controller
                .knownItemsForReordering()
                .first(matching: .nativeBoundary(for: address.section))
        else {
            return nil
        }
        return MacOS27MoveInstruction(
            item: item,
            destination: address.section == .visible
                ? .rightOfItem(iceItem)
                : .leftOfItem(iceItem),
            requiredSection: address.section
        )
    }

    /// Reads every currently managed owner once for final-order verification.
    /// Stale retained snapshots are deliberately not merged into a nonempty
    /// result: an absent hosted child must settle before a batch can pass.
    @available(macOS 27.0, *)
    private func currentMacOS27ReorderSnapshot(appState: AppState) async -> [MenuBarItem] {
        let knownItems = appState.menuBarManager.macOS27Controller.knownItemsForReordering()
        let sourcePIDs = Set(knownItems.map { $0.sourcePID ?? $0.ownerPID }).union([ProcessInfo.processInfo.processIdentifier])
        let namespaces = Set(knownItems.map(\.tag.namespace)).union([.ice])
        let refreshed = await Task.detached(priority: .userInitiated) {
            MacOS27MenuBarItemProvider.menuBarItems(
                sourcePIDs: sourcePIDs,
                namespaces: namespaces
            )
        }.value
        return refreshed
    }

    /// Compares the complete affected model, including the Ice boundary, rather
    /// than accepting one source/target pair that happened to be adjacent in a
    /// transient AX snapshot.
    @available(macOS 27.0, *)
    private func macOS27DesiredOrderStatus(
        desiredCache: ItemCache,
        appState: AppState
    ) async -> MacOS27DesiredOrderStatus {
        let physicalSections: [MenuBarSection.Name] = [
            .alwaysHidden,
            .hidden,
            .visible,
        ]
        var seenTags = Set<MenuBarItemTag>()
        let desiredTags: [MenuBarItemTag] = physicalSections.flatMap { section -> [MenuBarItemTag] in
            desiredCache[section].compactMap { item -> MenuBarItemTag? in
                guard macOS27TouchedMoveTags.contains(item.tag) else {
                    return nil
                }
                return seenTags.insert(item.tag).inserted
                    ? item.tag
                    : nil
            }
        }
        guard !desiredTags.isEmpty else { return .converged }

        let snapshot = await currentMacOS27ReorderSnapshot(appState: appState)
        let desiredTagSet = Set(desiredTags)
        let ordered = snapshot.sorted { $0.bounds.minX < $1.bounds.minX }
        let liveTags = ordered.compactMap { item in
            desiredTagSet.contains(item.tag) ? item.tag : nil
        }
        guard liveTags.count == desiredTags.count else { return .incomplete }

        if liveTags != desiredTags {
            for index in desiredTags.indices where desiredTags[index] != liveTags[index] {
                return .needsMove(desiredTags[index])
            }
            return .incomplete
        }

        for section in physicalSections {
            guard let boundaryIndex = ordered.firstIndex(matching: .nativeBoundary(for: section)) else {
                if desiredCache[section].isEmpty { continue }
                return .incomplete
            }
            for item in desiredCache[section] {
                guard macOS27TouchedMoveTags.contains(item.tag) else { continue }
                guard let itemIndex = ordered.firstIndex(matching: item.tag) else { return .incomplete }
                // Native hosted hit areas can overlap by a few points (notably
                // Text Input). Use the same ordinal contract as the drag step.
                let isOnCorrectSide = section == .visible
                    ? itemIndex > boundaryIndex
                    : itemIndex < boundaryIndex
                if !isOnCorrectSide {
                    return .needsMove(item.tag)
                }
            }
        }
        return .converged
    }

    @available(macOS 27.0, *)
    private func runMacOS27ReorderWorker() async {
        guard let appState else {
            macOS27ReorderTask = nil
            return
        }
        guard await waitForMacOS27DesiredOrderToSettle() else {
            macOS27ReorderTask = nil
            return
        }
        // Layout's idle state has no blank slots. Expose and align our own
        // boundary only for this explicit edit, without replacing its preview.
        guard await alignNativeHidingBoundary(updatingCache: false) else {
            await failMacOS27DesiredOrder(
                generation: macOS27DesiredGeneration, appState: appState, presentsAlert: false
            )
            return
        }

        var failedAttempts = 0
        var workerGeneration = macOS27DesiredGeneration
        var correctionAttempts = [MenuBarItemTag: Int]()

        while !Task.isCancelled {
            guard let desiredCache = macOS27DesiredCache else {
                macOS27ReorderTask = nil
                return
            }

            if workerGeneration != macOS27DesiredGeneration {
                workerGeneration = macOS27DesiredGeneration
                failedAttempts = 0
                correctionAttempts.removeAll()
                guard await waitForMacOS27DesiredOrderToSettle() else {
                    macOS27ReorderTask = nil
                    return
                }
                continue
            }

            if let sourceTag = macOS27PendingMoveOrder.first {
                let sourceGeneration = macOS27PendingMoveGenerations[sourceTag]
                guard
                    let instruction = macOS27MoveInstruction(
                        for: sourceTag,
                        desiredCache: desiredCache,
                        appState: appState
                    )
                else {
                    macOS27PendingMoveOrder.removeFirst()
                    macOS27PendingMoveGenerations[sourceTag] = nil
                    continue
                }

                do {
                    try await move(
                        item: instruction.item,
                        to: instruction.destination,
                        requiredSection: instruction.requiredSection,
                        coordinateMacOS27Move: false
                    )
                    if macOS27PendingMoveGenerations[sourceTag] == sourceGeneration {
                        macOS27PendingMoveOrder.removeAll { $0 == sourceTag }
                        macOS27PendingMoveGenerations[sourceTag] = nil
                    }
                    failedAttempts = 0
                } catch {
                    // A newer Layout edit makes this operation obsolete. Keep
                    // reconciling the latest desired state without surfacing an
                    // error for the discarded intermediate request.
                    if workerGeneration != macOS27DesiredGeneration {
                        continue
                    }
                    failedAttempts += 1
                    logger.warning(
                        "macOS 27 desired-order step failed (attempt \(failedAttempts, privacy: .public)): \(error, privacy: .public)"
                    )
                    if failedAttempts < 3 {
                        try? await Task.sleep(for: .milliseconds(180))
                        continue
                    }
                    await failMacOS27DesiredOrder(
                        generation: workerGeneration,
                        appState: appState,
                        presentsAlert: !(error is MacOS27ReorderError)
                    )
                    return
                }
                continue
            }

            let firstStatus = await macOS27DesiredOrderStatus(
                desiredCache: desiredCache,
                appState: appState
            )
            if workerGeneration != macOS27DesiredGeneration {
                continue
            }

            switch firstStatus {
            case .needsMove(let tag):
                correctionAttempts[tag, default: 0] += 1
                guard correctionAttempts[tag, default: 0] <= 3 else {
                    await failMacOS27DesiredOrder(
                        generation: workerGeneration, appState: appState, presentsAlert: false
                    )
                    return
                }
                macOS27PendingMoveGenerations[tag] = workerGeneration
                macOS27PendingMoveOrder.append(tag)
                continue
            case .incomplete:
                failedAttempts += 1
                if failedAttempts < 4 {
                    try? await Task.sleep(for: .milliseconds(180))
                    continue
                }
                await failMacOS27DesiredOrder(
                    generation: workerGeneration,
                    appState: appState,
                    presentsAlert: false
                )
                return
            case .converged:
                try? await Task.sleep(for: .milliseconds(140))
                guard workerGeneration == macOS27DesiredGeneration else { continue }
                let secondStatus = await macOS27DesiredOrderStatus(
                    desiredCache: desiredCache,
                    appState: appState
                )
                guard workerGeneration == macOS27DesiredGeneration else { continue }
                switch secondStatus {
                case .converged:
                    await completeMacOS27DesiredOrder(
                        generation: workerGeneration,
                        appState: appState
                    )
                    return
                case .needsMove(let tag):
                    correctionAttempts[tag, default: 0] += 1
                    guard correctionAttempts[tag, default: 0] <= 3 else {
                        await failMacOS27DesiredOrder(
                            generation: workerGeneration, appState: appState, presentsAlert: false
                        )
                        return
                    }
                    macOS27PendingMoveGenerations[tag] = workerGeneration
                    macOS27PendingMoveOrder.append(tag)
                case .incomplete:
                    failedAttempts += 1
                }
            }
        }

        macOS27ReorderTask = nil
    }

    @available(macOS 27.0, *)
    private func completeMacOS27DesiredOrder(
        generation: UInt64,
        appState: AppState
    ) async {
        guard generation == macOS27DesiredGeneration else { return }
        logger.notice("Committed macOS 27 desired menu bar order generation \(generation, privacy: .public)")
        macOS27PendingMoveOrder.removeAll()
        macOS27PendingMoveGenerations.removeAll()
        macOS27TouchedMoveTags.removeAll()
        macOS27DesiredCache = nil
        macOS27ProjectedCache = nil
        let controller = appState.menuBarManager.macOS27Controller
        controller.completePendingMove()
        controller.endReordering()
        macOS27ReorderTask = nil
        await cacheItemsRegardless(ignoringRecentMovement: true)
    }

    @available(macOS 27.0, *)
    private func failMacOS27DesiredOrder(
        generation: UInt64,
        appState: AppState,
        presentsAlert: Bool
    ) async {
        guard generation == macOS27DesiredGeneration else { return }
        logger.error("Could not reconcile macOS 27 with the final desired Layout order")
        macOS27PendingMoveOrder.removeAll()
        macOS27PendingMoveGenerations.removeAll()
        macOS27TouchedMoveTags.removeAll()
        macOS27DesiredCache = nil
        macOS27ProjectedCache = nil
        let controller = appState.menuBarManager.macOS27Controller
        controller.completePendingMove()
        controller.endReordering()
        macOS27ReorderTask = nil
        await cacheItemsRegardless(ignoringRecentMovement: true)
        guard
            presentsAlert,
            generation == macOS27DesiredGeneration,
            macOS27DesiredCache == nil
        else {
            return
        }
        NSAlert(error: EventError.cannotComplete).runModal()
    }

    @available(macOS 27.0, *)
    private func projectMacOS27CacheMove(
        item: MenuBarItem,
        to destination: MoveDestination
    ) {
        var projected = macOS27DesiredCache ?? itemCache
        for section in MenuBarSection.Name.allCases {
            projected[section].removeAll { $0.tag == item.tag }
        }
        projected.insert(item, at: destination)
        macOS27ProjectedCache = projected
        let cacheToDisplay = macOS27DesiredCache ?? projected
        if cacheToDisplay != itemCache {
            itemCache = cacheToDisplay
        }
    }

    /// Moves a menu bar item to the given destination.
    ///
    /// - Parameters:
    ///   - item: The menu bar item to move.
    ///   - destination: The destination to move the item to.
    func move(
        item: MenuBarItem,
        to destination: MoveDestination,
        requiredSection: MenuBarSection.Name? = nil,
        coordinateMacOS27Move: Bool = true
    ) async throws {
        guard item.tag != destination.targetItem.tag else {
            logger.debug("Ignoring a menu bar move whose item and target are identical")
            return
        }
        guard item.isMovable else {
            throw EventError.itemNotMovable(item)
        }
        guard let appState else {
            throw EventError.cannotComplete
        }

        if #available(macOS 27.0, *), coordinateMacOS27Move {
            enqueueMacOS27Move(
                item: item,
                to: destination,
                requiredSection: requiredSection
            )
            return
        }

        if #available(macOS 27.0, *) {
            try await macOS27MoveSemaphore.waitUnlessCancelled()
            defer { macOS27MoveSemaphore.signal() }

            // Reflect the requested order immediately while the physical move
            // is applied and verified. Layout has no animation, and a failed
            // or cancelled transaction restores this cache atomically.
            let cacheBeforeMove = itemCache
            projectMacOS27CacheMove(item: item, to: destination)
            var shouldRestoreProjectedCache = true
            defer {
                macOS27ProjectedCache = nil
                if
                    shouldRestoreProjectedCache,
                    macOS27DesiredCache == nil,
                    itemCache != cacheBeforeMove
                {
                    itemCache = cacheBeforeMove
                }
            }

            logger.log(
                "Assigning \(item.logString, privacy: .public) to \(destination.logString, privacy: .public) on macOS 27"
            )
            let knownItems = appState.menuBarManager.macOS27Controller.knownItemsForReordering()
            var requiredTags: Set<MenuBarItemTag> = [item.tag, destination.targetItem.tag]
            if requiredSection != nil {
                requiredTags.insert(.visibleControlItem)
                requiredTags.insert(.nativeBoundary(for: requiredSection ?? .visible))
            }
            let liveItems = await currentMacOS27Items(
                knownItems: knownItems,
                item: item,
                destination: destination,
                requiring: requiredTags
            )
            guard
                let liveItem = liveItems.first(where: { $0.tag == item.tag }),
                let liveTarget = liveItems.first(where: {
                    $0.tag == destination.targetItem.tag
                })
            else {
                // Hosted items such as Spotlight can disappear for one AX
                // sample while MenuBarAgent republishes them. Let the desired-
                // order worker retry against a stable snapshot instead of
                // treating an obsolete intermediate request as successful.
                logger.notice("macOS 27 move endpoint is temporarily unavailable")
                throw MacOS27ReorderError.endpointUnavailable
            }
            func resolvedDestination(for target: MenuBarItem) -> MoveDestination {
                switch destination {
                case .leftOfItem: .leftOfItem(target)
                case .rightOfItem: .rightOfItem(target)
                }
            }
            let liveDestination = resolvedDestination(for: liveTarget)
            var didMove = macOS27ItemHasCorrectPosition(
                item: liveItem,
                for: liveDestination,
                among: liveItems,
                requiredSection: requiredSection
            )

            // Drag directly to the requested native neighbor. Do not insert
            // a preference-write or boundary-only move before the real move.
            if !didMove {
                var moveItems = liveItems
                var moveItem = liveItem
                var moveDestination = liveDestination

                if requiredSection != nil {
                    // A preceding section move can still be republishing its
                    // hosted scenes after releasing the move semaphore. Take
                    // one targeted boundary snapshot for cross-section work;
                    // same-section adjustments keep the single-scan fast path.
                    let refreshedItems = await currentMacOS27Items(
                        knownItems: knownItems,
                        item: liveItem,
                        destination: liveDestination,
                        requiring: requiredTags
                    )
                    if
                        let refreshedItem = refreshedItems.first(where: { $0.tag == item.tag }),
                        let refreshedTarget = refreshedItems.first(where: {
                            $0.tag == destination.targetItem.tag
                        })
                    {
                        moveItems = refreshedItems
                        moveItem = refreshedItem
                        moveDestination = resolvedDestination(for: refreshedTarget)
                        didMove = macOS27ItemHasCorrectPosition(
                            item: moveItem,
                            for: moveDestination,
                            among: moveItems,
                            requiredSection: requiredSection
                        )
                    }
                }

                if !didMove {
                    didMove = await performMacOS27NativeMove(
                        item: moveItem,
                        destination: moveDestination,
                        contextItems: moveItems,
                        appState: appState,
                        requiredSection: requiredSection
                    )
                }
            }

            guard didMove else {
                logger.warning("Could not verify the requested macOS 27 reorder")
                throw EventError.cannotComplete
            }

            // Persist and project only after the real AX order agrees. This
            // prevents Layout from displaying an optimistic permutation that
            // snaps back on its deferred cache refresh.
            let resolvedSection = appState.menuBarManager.macOS27Controller.move(
                item: liveItem,
                to: liveDestination,
                currentCache: cacheBeforeMove,
                requiredSection: requiredSection
            )
            if let requiredSection, resolvedSection != requiredSection {
                logger.error("macOS 27 move resolved to an unexpected Layout section")
            }
            projectMacOS27CacheMove(item: liveItem, to: liveDestination)
            macOS27ProjectedCache = nil
            shouldRestoreProjectedCache = false
            return
        }

        try await waitForUserToPauseInput()

        appState.hidEventManager.stopAll()
        defer {
            appState.hidEventManager.startAll()
        }

        try await waitForMoveOperationBuffer()

        logger.log(
            """
            Moving \(item.logString, privacy: .public) to \
            \(destination.logString, privacy: .public)
            """
        )

        guard try await !itemHasCorrectPosition(item: item, for: destination) else {
            logger.debug("Item has correct position, cancelling move")
            return
        }

        MouseHelpers.hideCursor()
        defer {
            MouseHelpers.showCursor()
        }

        let maxAttempts = 8
        for n in 1...maxAttempts {
            guard !Task.isCancelled else {
                throw EventError.cannotComplete
            }
            do {
                if try await itemHasCorrectPosition(item: item, for: destination) {
                    logger.debug("Item has correct position, finished with move")
                    return
                }
                try await postMoveEvents(item: item, destination: destination)
                logger.debug("Attempt \(n, privacy: .public) succeeded, finished with move")
                return
            } catch {
                logger.debug("Attempt \(n, privacy: .public) failed: \(error, privacy: .public)")
                if n < maxAttempts {
                    try await waitForMoveOperationBuffer()
                    continue
                }
                if error is EventError {
                    throw error
                }
                throw EventError.cannotComplete
            }
        }
    }

    /// Moves an item into a section that currently has no other item to use as
    /// a Layout drag destination.
    func move(item: MenuBarItem, toSection section: MenuBarSection.Name) async throws {
        guard #available(macOS 27.0, *), appState != nil else {
            throw EventError.cannotComplete
        }
        guard item.isMovable else {
            throw EventError.itemNotMovable(item)
        }
        enqueueMacOS27Move(item: item, toSection: section)
    }
}

// MARK: - Clicking Items

extension MenuBarItemManager {
    /// Returns the equivalent event subtypes for clicking a menu bar
    /// item with the given mouse button.
    private nonisolated func getClickSubtypes(
        for mouseButton: CGMouseButton
    ) -> (down: MenuBarItemEventType.ClickSubtype, up: MenuBarItemEventType.ClickSubtype) {
        switch mouseButton {
        case .left: (.leftMouseDown, .leftMouseUp)
        case .right: (.rightMouseDown, .rightMouseUp)
        default: (.otherMouseDown, .otherMouseUp)
        }
    }

    /// Creates and posts a series of events to click a menu bar item.
    ///
    /// - Parameters:
    ///   - item: The menu bar item to click.
    ///   - mouseButton: The mouse button to click the item with.
    private func postClickEvents(item: MenuBarItem, mouseButton: CGMouseButton) async throws {
        try await eventSemaphore.waitUnlessCancelled()
        defer {
            eventSemaphore.signal()
        }

        let clickPoint = try await getCurrentBounds(for: item).center
        let mouseLocation = try getMouseLocation()
        let source = try getEventSource()

        try permitLocalEvents()

        let clickTypes = getClickSubtypes(for: mouseButton)
        let timeout = Duration.milliseconds(250)

        guard
            let mouseDown = CGEvent.menuBarItemEvent(
                item: item,
                source: source,
                type: .click(clickTypes.down),
                location: clickPoint
            ),
            let mouseUp = CGEvent.menuBarItemEvent(
                item: item,
                source: source,
                type: .click(clickTypes.up),
                location: clickPoint
            )
        else {
            throw EventError.eventCreationFailure(item)
        }

        MouseHelpers.hideCursor()
        defer {
            MouseHelpers.warpCursor(to: mouseLocation)
            MouseHelpers.showCursor()
        }

        do {
            try await postEventWithBarrier(
                mouseDown,
                to: item,
                timeout: timeout
            )
            try await postEventWithBarrier(
                mouseUp,
                to: item,
                timeout: timeout,
                repeating: 2 // Double mouse up prevents invalid item state.
            )
        } catch {
            do {
                logger.warning("Click events failed, posting fallback")
                try await postEventWithBarrier(
                    mouseUp,
                    to: item,
                    timeout: timeout,
                    repeating: 2 // Double mouse up prevents invalid item state.
                )
            } catch {
                // Catch this for logging purposes only. We want to propagate
                // the original error.
                logger.error("Fallback failed with error: \(error, privacy: .public)")
            }
            throw error
        }
    }

    /// Clicks a menu bar item with the given mouse button.
    ///
    /// - Parameters:
    ///   - item: The menu bar item to click.
    ///   - mouseButton: The mouse button to click the item with.
    func click(item: MenuBarItem, with mouseButton: CGMouseButton) async throws {
        guard #unavailable(macOS 27.0) else { throw EventError.cannotComplete }
        guard let appState else {
            throw EventError.cannotComplete
        }

        try await waitForUserToPauseInput()

        logger.log(
            """
            Clicking \(item.logString, privacy: .public) with \
            \(mouseButton.logString, privacy: .public)
            """
        )

        appState.hidEventManager.stopAll()
        defer {
            appState.hidEventManager.startAll()
        }

        let maxAttempts = 4
        for n in 1...maxAttempts {
            guard !Task.isCancelled else {
                throw EventError.cannotComplete
            }
            do {
                try await postClickEvents(item: item, mouseButton: mouseButton)
                logger.debug("Attempt \(n, privacy: .public) succeeded, finished with click")
                return
            } catch {
                logger.debug("Attempt \(n, privacy: .public) failed: \(error, privacy: .public)")
                if n < maxAttempts {
                    await eventSleep()
                    continue
                }
                if error is EventError {
                    throw error
                }
                throw EventError.cannotComplete
            }
        }
    }
}

// MARK: - Temporarily Showing Items

extension MenuBarItemManager {
    /// Context for a temporarily shown menu bar item.
    private final class TemporarilyShownItemContext {
        /// The tag associated with the item.
        let tag: MenuBarItemTag

        /// The destination to return the item to.
        let returnDestination: MoveDestination

        /// The window of the item's shown interface.
        var shownInterfaceWindow: WindowInfo?

        /// The number of attempts that have been made to rehide the item.
        var rehideAttempts = 0

        /// A Boolean value that indicates whether the menu bar item's
        /// interface is showing.
        var isShowingInterface: Bool {
            guard
                let window = shownInterfaceWindow,
                let current = WindowInfo(windowID: window.windowID)
            else {
                // Window no longer exists, so assume closed.
                return false
            }
            if
                current.layer != CGWindowLevelForKey(.popUpMenuWindow),
                current.layer != CGWindowLevelForKey(.popUpMenuWindow) - 1,
                current.layer != CGWindowLevelForKey(.statusWindow),
                current.layer != CGWindowLevelForKey(.mainMenuWindow),
                let app = current.owningApplication
            {
                return app.isActive && current.isOnScreen
            }
            return current.isOnScreen
        }

        init(tag: MenuBarItemTag, returnDestination: MoveDestination) {
            self.tag = tag
            self.returnDestination = returnDestination
        }
    }

    /// Gets the destination to return the given item to after it is
    /// temporarily shown.
    private func getReturnDestination(for item: MenuBarItem, in items: [MenuBarItem]) -> MoveDestination? {
        guard let index = items.firstIndex(matching: item.tag) else {
            return nil
        }
        if items.indices.contains(index + 1) {
            return .leftOfItem(items[index + 1])
        }
        if items.indices.contains(index - 1) {
            return .rightOfItem(items[index - 1])
        }
        return nil
    }

    /// Schedules a timer for the given interval that rehides the
    /// temporarily shown items when fired.
    private func runRehideTimer(for interval: TimeInterval? = nil) {
        guard let appState else {
            return
        }
        let interval = interval ?? appState.settings.advanced.tempShowInterval
        logger.debug("Running rehide timer for interval: \(interval, format: .fixed, privacy: .public)")
        rehideTimer?.invalidate()
        rehideTimer = .scheduledTimer(withTimeInterval: interval, repeats: false) { [weak self] timer in
            guard let self else {
                timer.invalidate()
                return
            }
            logger.debug("Rehide timer fired")
            Task {
                await self.rehideTemporarilyShownItems()
            }
        }
    }

    /// Temporarily shows the given item.
    ///
    /// The item is cached and returned to its original location after the
    /// time interval specified by ``AdvancedSettings/tempShowInterval``.
    ///
    /// - Parameters:
    ///   - item: The item to temporarily show.
    ///   - mouseButton: The mouse button to click the item with.
    func temporarilyShow(item: MenuBarItem, clickingWith mouseButton: CGMouseButton) async {
        guard let appState else {
            logger.error("Missing AppState, so not showing \(item.logString, privacy: .public)")
            return
        }

        if #available(macOS 27.0, *) {
            // Native menu items are operated in the menu bar, never proxied
            // through Ice's Search/Ice Bar interfaces on macOS 27.
            return
        }
        guard let screen = NSScreen.screenWithActiveMenuBar else {
            logger.error("No active menu bar screen, so not showing \(item.logString, privacy: .public)")
            return
        }

        guard let applicationMenuFrame = screen.getApplicationMenuFrame() else {
            logger.error("No application menu frame, so not showing \(item.logString, privacy: .public)")
            return
        }

        var items = await MenuBarItem.getMenuBarItems(option: .activeSpace)

        guard let destination = getReturnDestination(for: item, in: items) else {
            logger.error("No return destination for \(item.logString, privacy: .public)")
            return
        }

        // Remove all items up to and including the hidden control item.
        if let index = items.firstIndex(matching: .hiddenControlItem) {
            items.removeSubrange(...index)
        }

        let maxX: CGFloat = {
            var maxX = applicationMenuFrame.maxX
            if let frameOfNotch = screen.frameOfNotch {
                maxX = max(maxX, frameOfNotch.maxX + 30)
            }
            return maxX + item.bounds.width
        }()

        // Remove items until we have enough room to show this item.
        items.trimPrefix { item in
            if item.isOnScreen && item.canBeHidden {
                return item.bounds.minX <= maxX
            }
            return true
        }

        guard let targetItem = items.first else {
            logger.warning("Not enough room to show \(item.logString, privacy: .public)")
            let alert = NSAlert()
            alert.messageText = "Not enough room to show \"\(item.displayName)\""
            alert.runModal()
            return
        }

        appState.hidEventManager.stopAll()
        defer {
            appState.hidEventManager.startAll()
        }

        logger.debug("Temporarily showing \(item.logString, privacy: .public)")

        do {
            try await move(item: item, to: .leftOfItem(targetItem))
        } catch {
            logger.error("Error showing item: \(error, privacy: .public)")
            return
        }

        let context = TemporarilyShownItemContext(tag: item.tag, returnDestination: destination)
        temporarilyShownItemContexts.append(context)

        rehideTimer?.invalidate()
        defer {
            runRehideTimer()
        }

        await eventSleep(for: .milliseconds(100))
        let idsBeforeClick = Set(Bridging.getWindowList(option: .onScreen))

        do {
            try await click(item: item, with: mouseButton)
        } catch {
            logger.error("Error clicking item: \(error, privacy: .public)")
            return
        }

        await eventSleep(for: .milliseconds(250))
        let windowsAfterClick = WindowInfo.createWindows(option: .onScreen)

        context.shownInterfaceWindow = windowsAfterClick.first { window in
            window.ownerPID == item.sourcePID && !idsBeforeClick.contains(window.windowID)
        }
    }

    /// Rehides all temporarily shown items.
    ///
    /// If an item is currently showing its interface, this method waits
    /// for the interface to close before hiding the items.
    func rehideTemporarilyShownItems() async {
        guard let appState else {
            logger.error("Missing AppState, so not rehiding")
            return
        }
        guard !temporarilyShownItemContexts.isEmpty else {
            return
        }
        guard !temporarilyShownItemContexts.contains(where: { $0.isShowingInterface }) else {
            logger.debug("Menu bar item interface is shown, so waiting to rehide")
            runRehideTimer(for: 3)
            return
        }
        guard hasUserPausedInput(for: .milliseconds(250)) else {
            logger.debug("Found recent user input, so waiting to rehide")
            runRehideTimer(for: 1)
            return
        }

        var currentContexts = temporarilyShownItemContexts
        temporarilyShownItemContexts.removeAll()

        let items = await MenuBarItem.getMenuBarItems(option: .activeSpace)
        var failedContexts = [TemporarilyShownItemContext]()

        appState.hidEventManager.stopAll()
        defer {
            appState.hidEventManager.startAll()
        }

        await eventSleep(for: .milliseconds(250))

        logger.debug("Rehiding temporarily shown items")

        MouseHelpers.hideCursor()
        defer {
            MouseHelpers.showCursor()
        }

        while let context = currentContexts.popLast() {
            guard let item = items.first(matching: context.tag) else {
                continue
            }
            do {
                try await move(item: item, to: context.returnDestination)
            } catch {
                context.rehideAttempts += 1
                logger.warning(
                    """
                    Attempt \(context.rehideAttempts, privacy: .public) to rehide \
                    \(item.logString, privacy: .public) failed with error: \
                    \(error, privacy: .public)
                    """
                )
                if context.rehideAttempts < 3 {
                    currentContexts.append(context) // Try again.
                } else {
                    // Failed contexts are ultimately added back to the array
                    // and rehidden after a longer delay, so reset the count.
                    context.rehideAttempts = 0
                    failedContexts.append(context)
                }
            }
        }

        if failedContexts.isEmpty {
            logger.debug("All items were successfully rehidden")
        } else {
            logger.error(
                """
                Some items failed to rehide: \
                \(failedContexts.map { $0.tag }, privacy: .public)
                """
            )
            temporarilyShownItemContexts.append(contentsOf: failedContexts.reversed())
            runRehideTimer(for: 3)
        }
    }

    /// Removes a temporarily shown item from the cache, ensuring that
    /// the item is _not_ returned to its original location.
    func removeTemporarilyShownItemFromCache(with tag: MenuBarItemTag) {
        while let index = temporarilyShownItemContexts.firstIndex(where: { $0.tag == tag }) {
            logger.debug(
                """
                Removing temporarily shown item from cache: \
                \(tag, privacy: .public)
                """
            )
            temporarilyShownItemContexts.remove(at: index)
        }
    }
}

// MARK: - Control Item Order

extension MenuBarItemManager {
    /// Enforces the order of the given control items, ensuring that the
    /// control item for the always-hidden section is positioned to the
    /// left of control item for the hidden section.
    private func enforceControlItemOrder(controlItems: ControlItemPair) async {
        let hidden = controlItems.hidden

        guard
            let alwaysHidden = controlItems.alwaysHidden,
            hidden.bounds.maxX <= alwaysHidden.bounds.minX
        else {
            return
        }

        do {
            logger.debug("Control items have incorrect order")
            try await move(item: alwaysHidden, to: .leftOfItem(hidden))
        } catch {
            logger.error("Error enforcing control item order: \(error, privacy: .public)")
        }
    }
}

// MARK: - MenuBarItemEventType

/// Event types for menu bar item events.
private enum MenuBarItemEventType {
    /// The event type for moving a menu bar item.
    case move(MoveSubtype)
    /// The event type for clicking a menu bar item.
    case click(ClickSubtype)

    var cgEventType: CGEventType {
        switch self {
        case .move(let subtype): subtype.cgEventType
        case .click(let subtype): subtype.cgEventType
        }
    }

    var cgEventFlags: CGEventFlags {
        switch self {
        case .move(.mouseDown): .maskCommand
        case .move, .click: []
        }
    }

    var cgMouseButton: CGMouseButton {
        switch self {
        case .move: .left
        case .click(let subtype): subtype.cgMouseButton
        }
    }

    // MARK: Subtypes

    /// Subtype for menu bar item move events.
    enum MoveSubtype {
        case mouseDown
        case mouseUp

        var cgEventType: CGEventType {
            switch self {
            case .mouseDown: .leftMouseDown
            case .mouseUp: .leftMouseUp
            }
        }
    }

    /// Subtype for menu bar item click events.
    enum ClickSubtype {
        case leftMouseDown
        case leftMouseUp
        case rightMouseDown
        case rightMouseUp
        case otherMouseDown
        case otherMouseUp

        var cgEventType: CGEventType {
            switch self {
            case .leftMouseDown: .leftMouseDown
            case .leftMouseUp: .leftMouseUp
            case .rightMouseDown: .rightMouseDown
            case .rightMouseUp: .rightMouseUp
            case .otherMouseDown: .otherMouseDown
            case .otherMouseUp: .otherMouseUp
            }
        }

        var cgMouseButton: CGMouseButton {
            switch self {
            case .leftMouseDown, .leftMouseUp: .left
            case .rightMouseDown, .rightMouseUp: .right
            case .otherMouseDown, .otherMouseUp: .center
            }
        }

        var clickState: Int64 {
            switch self {
            case .leftMouseDown, .rightMouseDown, .otherMouseDown: 1
            case .leftMouseUp, .rightMouseUp, .otherMouseUp: 0
            }
        }
    }
}

// MARK: - CGEventField Helpers

private extension CGEventField {
    /// Key to access a field that contains the event's window identifier.
    static let windowID = CGEventField(rawValue: 0x33)! // swiftlint:disable:this force_unwrapping

    /// Fields that can be used to compare menu bar item events.
    static let menuBarItemEventFields: [CGEventField] = [
        .eventSourceUserData,
        .mouseEventWindowUnderMousePointer,
        .mouseEventWindowUnderMousePointerThatCanHandleThisEvent,
        .windowID,
    ]
}

// MARK: - CGEventFilterMask Helpers

private extension CGEventFilterMask {
    /// Specifies that all events should be permitted during event suppression states.
    static let permitAllEvents: CGEventFilterMask = [
        .permitLocalMouseEvents,
        .permitLocalKeyboardEvents,
        .permitSystemDefinedEvents,
    ]
}

// MARK: - CGEventType Helpers

private extension CGEventType {
    /// A string to use for logging purposes.
    var logString: String {
        switch self {
        case .null: "null event"
        case .leftMouseDown: "leftMouseDown event"
        case .leftMouseUp: "leftMouseUp event"
        case .rightMouseDown: "rightMouseDown event"
        case .rightMouseUp: "rightMouseUp event"
        case .mouseMoved: "mouseMoved event"
        case .leftMouseDragged: "leftMouseDragged event"
        case .rightMouseDragged: "rightMouseDragged event"
        case .keyDown: "keyDown event"
        case .keyUp: "keyUp event"
        case .flagsChanged: "flagsChanged event"
        case .scrollWheel: "scrollWheel event"
        case .tabletPointer: "tabletPointer event"
        case .tabletProximity: "tabletProximity event"
        case .otherMouseDown: "otherMouseDown event"
        case .otherMouseUp: "otherMouseUp event"
        case .otherMouseDragged: "otherMouseDragged event"
        case .tapDisabledByTimeout: "tapDisabledByTimeout event"
        case .tapDisabledByUserInput: "tapDisabledByUserInput event"
        @unknown default: "unknown event"
        }
    }
}

// MARK: - CGMouseButton Helpers

private extension CGMouseButton {
    /// A string to use for logging purposes.
    var logString: String {
        switch self {
        case .left: "left mouse button"
        case .right: "right mouse button"
        case .center: "center mouse button"
        @unknown default: "unknown mouse button"
        }
    }
}

// MARK: - CGEvent Helpers

private extension CGEvent {
    /// Returns an event that can be sent to a menu bar item.
    ///
    /// - Parameters:
    ///   - item: The event's target item.
    ///   - source: The event's source.
    ///   - type: The event's specialized type.
    ///   - location: The event's location. Does not need to be
    ///     within the bounds of the item.
    static func menuBarItemEvent(
        item: MenuBarItem,
        source: CGEventSource,
        type: MenuBarItemEventType,
        location: CGPoint
    ) -> CGEvent? {
        guard let event = CGEvent(
            mouseEventSource: source,
            mouseType: type.cgEventType,
            mouseCursorPosition: location,
            mouseButton: type.cgMouseButton
        ) else {
            return nil
        }
        event.setFlags(for: type)
        event.setUserData(ObjectIdentifier(event))
        event.setWindowID(item.windowID, for: type)
        event.setClickState(for: type)
        return event
    }

    /// Returns a null event with unique user data.
    static func uniqueNullEvent() -> CGEvent? {
        guard let event = CGEvent(source: nil) else {
            return nil
        }
        event.setUserData(ObjectIdentifier(event))
        return event
    }

    /// Posts the event to the given event tap location.
    ///
    /// - Parameter location: The event tap location to post the event to.
    func post(to location: EventTap.Location) {
        let type = self.type
        Logger.menuBarItemManager.debug(
            """
            Posting \(type.logString, privacy: .public) \
            to \(location.logString, privacy: .public)
            """
        )
        switch location {
        case .hidEventTap: post(tap: .cghidEventTap)
        case .sessionEventTap: post(tap: .cgSessionEventTap)
        case .annotatedSessionEventTap: post(tap: .cgAnnotatedSessionEventTap)
        case .pid(let pid): postToPid(pid)
        }
    }

    /// Returns a Boolean value that indicates whether the given integer
    /// fields from this event are equivalent to the same integer fields
    /// from the specified event.
    ///
    /// - Parameters:
    ///   - other: The event to compare with this event.
    ///   - fields: The integer fields to check.
    func matches(_ other: CGEvent, byIntegerFields fields: [CGEventField]) -> Bool {
        fields.allSatisfy { field in
            getIntegerValueField(field) == other.getIntegerValueField(field)
        }
    }

    func setTargetPID(_ pid: pid_t) {
        let targetPID = Int64(pid)
        setIntegerValueField(.eventTargetUnixProcessID, value: targetPID)
    }

    private func setFlags(for type: MenuBarItemEventType) {
        flags = type.cgEventFlags
    }

    private func setUserData(_ bitPattern: ObjectIdentifier) {
        let userData = Int64(Int(bitPattern: bitPattern))
        setIntegerValueField(.eventSourceUserData, value: userData)
    }

    private func setWindowID(_ windowID: CGWindowID, for type: MenuBarItemEventType) {
        let windowID = Int64(windowID)

        setIntegerValueField(.mouseEventWindowUnderMousePointer, value: windowID)
        setIntegerValueField(.mouseEventWindowUnderMousePointerThatCanHandleThisEvent, value: windowID)

        if case .move = type {
            setIntegerValueField(.windowID, value: windowID)
        }
    }

    private func setClickState(for type: MenuBarItemEventType) {
        if case .click(let subtype) = type {
            setIntegerValueField(.mouseEventClickState, value: subtype.clickState)
        }
    }
}

// MARK: - Logger Helpers

private extension Logger {
    /// Logger for the menu bar item manager.
    static let menuBarItemManager = Logger(category: "MenuBarItemManager")
}
