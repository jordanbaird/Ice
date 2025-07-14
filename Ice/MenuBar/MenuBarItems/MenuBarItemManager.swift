//
//  MenuBarItemManager.swift
//  Ice
//

import Cocoa
import Combine
import OSLog

/// Manager for menu bar items.
@MainActor
final class MenuBarItemManager: ObservableObject {
    /// Cache for menu bar items.
    struct ItemCache: Hashable {
        /// All cached menu bar items, keyed by section.
        private var items = [MenuBarSection.Name: [MenuBarItem]]()

        /// All cached menu bar items.
        var allItems: [MenuBarItem] {
            MenuBarSection.Name.allCases.reduce(into: []) { result, section in
                result.append(contentsOf: self[section])
            }
        }

        /// The cached menu bar items managed by Ice.
        var managedItems: [MenuBarItem] {
            MenuBarSection.Name.allCases.reduce(into: []) { result, section in
                result.append(contentsOf: managedItems(for: section))
            }
        }

        /// Clears the cache.
        mutating func clear() {
            items.removeAll()
        }

        /// Returns the cached menu bar items managed by Ice for the given section.
        func managedItems(for section: MenuBarSection.Name) -> [MenuBarItem] {
            self[section].filter { item in
                // Filter out items that can't be hidden.
                if !item.canBeHidden {
                    return false
                }

                // Filter out the two separator control items.
                if item.isControlItem && item.tag != .visibleControlItem {
                    return false
                }

                return true
            }
        }

        /// Returns the name of the section for the given menu bar item.
        func section(for item: MenuBarItem) -> MenuBarSection.Name? {
            for (section, items) in self.items where items.contains(where: { $0.tag == item.tag }) {
                return section
            }
            return nil
        }

        /// Accesses the items in the given section.
        subscript(section: MenuBarSection.Name) -> [MenuBarItem] {
            get { items[section, default: []] }
            set { items[section] = newValue }
        }
    }

    /// Context for a temporarily shown menu bar item.
    private struct TempShownItemContext {
        /// The tag associated with the item.
        let tag: MenuBarItemTag

        /// The destination to return the item to.
        let returnDestination: MoveDestination

        /// The window of the item's shown interface.
        let shownInterfaceWindow: WindowInfo?

        /// A Boolean value that indicates whether the menu bar item's interface is showing.
        var isShowingInterface: Bool {
            guard let currentWindow = shownInterfaceWindow.flatMap({ WindowInfo(windowID: $0.windowID) }) else {
                return false
            }
            return if
                currentWindow.layer != CGWindowLevelForKey(.popUpMenuWindow),
                let owningApplication = currentWindow.owningApplication
            {
                owningApplication.isActive && currentWindow.isOnScreen
            } else {
                currentWindow.isOnScreen
            }
        }
    }

    /// The manager's menu bar item cache.
    @Published private(set) var itemCache = ItemCache()

    /// The shared app state.
    private(set) weak var appState: AppState?

    /// Logger for the menu bar item manager.
    private let logger = Logger(category: "MenuBarItemManager")

    /// Storage for internal observers.
    private var cancellables = Set<AnyCancellable>()

    /// Cached window identifiers for the most recent items.
    private var cachedItemWindowIDs = [CGWindowID]()

    /// Context values for the current temporarily shown items.
    private var tempShownItemContexts = [TempShownItemContext]()

    /// A timer that determines when to rehide the temporarily shown items.
    private var tempShownItemsTimer: Timer?

    /// The last time a menu bar item was moved.
    private var lastItemMoveStartDate: Date?

    /// A Boolean value that indicates whether a menu bar item has
    /// recently moved.
    var itemHasRecentlyMoved: Bool {
        guard let lastItemMoveStartDate else {
            return false
        }
        return Date.now.timeIntervalSince(lastItemMoveStartDate) <= 1
    }

    /// Sets up the manager.
    func performSetup(with appState: AppState) {
        self.appState = appState
        configureCancellables(with: appState)
    }

    /// Configures the internal observers for the manager.
    private func configureCancellables(with appState: AppState) {
        var c = Set<AnyCancellable>()

        Publishers.CombineLatest(
            Timer.publish(every: 5, on: .main, in: .default)
                .autoconnect()
                .merge(with: Just(.now)),
            NSWorkspace.shared.publisher(for: \.runningApplications)
                .delay(for: 0.25, scheduler: DispatchQueue.main)
        )
        .throttle(for: 1, scheduler: DispatchQueue.main, latest: true)
        .sink { [weak self] _ in
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
                guard let self, identifier == .menuBarLayout else {
                    return
                }
                Task {
                    await self.cacheItemsRegardless()
                }
            }
            .store(in: &c)

        cancellables = c
    }
}

// MARK: - Cache Items

extension MenuBarItemManager {
    private struct ControlItemSet {
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

    /// Caches the given menu bar items, without ensuring that the
    /// control items are in the correct order.
    private func uncheckedCacheItems(controlItems: ControlItemSet, otherItems: [MenuBarItem]) {
        logger.debug("Caching menu bar items")

        let predicates = Predicates.sectionPredicates(
            hiddenControlItem: controlItems.hidden,
            alwaysHiddenControlItem: controlItems.alwaysHidden
        )

        var cache = ItemCache()
        var tempShownItems = [(MenuBarItem, MoveDestination)]()

        for item in otherItems {
            if let context = tempShownItemContexts.first(where: { $0.tag == item.tag }) {
                // Keep track of temporarily shown items and their return destinations separately.
                // We want to cache them as if they were in their original locations. Once all other
                // items are cached, use the return destinations to insert the items into the cache
                // at the correct position.
                tempShownItems.append((item, context.returnDestination))
            } else if predicates.isInVisibleSection(item) {
                cache[.visible].append(item)
            } else if predicates.isInHiddenSection(item) {
                cache[.hidden].append(item)
            } else if predicates.isInAlwaysHiddenSection(item) {
                cache[.alwaysHidden].append(item)
            } else {
                logger.warning("\(item.logString, privacy: .public) was not cached")
                cachedItemWindowIDs.removeAll() // Make sure we don't skip the next cache attempt.
            }
        }

        for (item, destination) in tempShownItems {
            switch destination {
            case .leftOfItem(let targetItem):
                switch targetItem.tag {
                case .hiddenControlItem:
                    cache[.hidden].append(item)
                case .alwaysHiddenControlItem:
                    cache[.alwaysHidden].append(item)
                default:
                    guard
                        let section = cache.section(for: targetItem),
                        let index = cache[section].firstIndex(matching: targetItem.tag)
                    else {
                        continue
                    }
                    let range = cache[section].startIndex...cache[section].endIndex
                    cache[section].insert(item, at: index.clamped(to: range))
                }
            case .rightOfItem(let targetItem):
                switch targetItem.tag {
                case .hiddenControlItem:
                    cache[.visible].insert(item, at: 0)
                case .alwaysHiddenControlItem:
                    cache[.hidden].insert(item, at: 0)
                default:
                    guard
                        let section = cache.section(for: targetItem),
                        let index = cache[section].firstIndex(matching: targetItem.tag)
                    else {
                        continue
                    }
                    let range = cache[section].startIndex...cache[section].endIndex
                    cache[section].insert(item, at: (index - 1).clamped(to: range))
                }
            }
        }

        itemCache = cache
    }

    /// Caches the current menu bar items, regardless of the current item
    /// state, ensuring that the control items are in the correct order.
    func cacheItemsRegardless(_ currentItemWindowIDs: [CGWindowID]? = nil) async {
        var items = MenuBarItem.getMenuBarItems(option: .activeSpace)
        cachedItemWindowIDs = currentItemWindowIDs ?? items.reversed().map { $0.windowID }

        guard let controlItems = ControlItemSet(items: &items) else {
            logger.warning("Missing control item for hidden section")
            logger.debug("Clearing menu bar item cache")
            itemCache.clear()
            return
        }

        await enforceControlItemOrder(controlItems: controlItems)
        uncheckedCacheItems(controlItems: controlItems, otherItems: items)
    }

    /// Caches the current menu bar items if needed, ensuring that the
    /// control items are in the correct order.
    func cacheItemsIfNeeded() async {
        guard !itemHasRecentlyMoved else {
            logger.debug("Skipping menu bar item cache as an item was recently moved")
            return
        }

        let itemWindowIDs = Bridging.getMenuBarWindowList(option: [.itemsOnly, .activeSpace])

        if
            cachedItemWindowIDs == itemWindowIDs,
            itemCache.managedItems.allSatisfy({ $0.sourcePID != nil })
        {
            logger.debug("Skipping menu bar item cache as item windows have not changed")
            return
        }

        await cacheItemsRegardless(itemWindowIDs)
    }
}

// MARK: - Menu Bar Item Events -

extension MenuBarItemManager {
    /// An error that can occur during menu bar item event operations.
    struct EventError: Error, CustomStringConvertible, LocalizedError {
        /// Error codes within the domain of menu bar item event errors.
        enum ErrorCode: Int, CustomStringConvertible {
            /// An operation could not be completed.
            case couldNotComplete
            /// The creation of a menu bar item event failed.
            case eventCreationFailure
            /// The shared app state is invalid or could not be found.
            case invalidAppState
            /// An event source could not be created or is otherwise invalid.
            case invalidEventSource
            /// The location of the mouse cursor is invalid or could not be found.
            case invalidCursorLocation
            /// A menu bar item is invalid.
            case invalidItem
            /// A menu bar item cannot be moved.
            case notMovable
            /// A menu bar item event operation timed out.
            case eventOperationTimeout
            /// A menu bar item bounds check timed out.
            case boundsCheckTimeout
            /// An operation timed out.
            case otherTimeout

            /// Description of the code for debugging purposes.
            var description: String {
                switch self {
                case .couldNotComplete: "couldNotComplete"
                case .eventCreationFailure: "eventCreationFailure"
                case .invalidAppState: "invalidAppState"
                case .invalidEventSource: "invalidEventSource"
                case .invalidCursorLocation: "invalidCursorLocation"
                case .invalidItem: "invalidItem"
                case .notMovable: "notMovable"
                case .eventOperationTimeout: "eventOperationTimeout"
                case .boundsCheckTimeout: "boundsCheckTimeout"
                case .otherTimeout: "otherTimeout"
                }
            }

            /// A string to use for logging purposes.
            var logString: String {
                "\(self) (rawValue: \(rawValue))"
            }
        }

        /// The error code of this error.
        let code: ErrorCode

        /// The error's menu bar item.
        let item: MenuBarItem

        /// The message associated with this error.
        var message: String {
            switch code {
            case .couldNotComplete:
                "Could not complete event operation for \"\(item.displayName)\""
            case .eventCreationFailure:
                "Failed to create event for \"\(item.displayName)\""
            case .invalidAppState:
                "Invalid app state for \"\(item.displayName)\""
            case .invalidEventSource:
                "Invalid event source for \"\(item.displayName)\""
            case .invalidCursorLocation:
                "Invalid cursor location for \"\(item.displayName)\""
            case .invalidItem:
                "\"\(item.displayName)\" is invalid"
            case .notMovable:
                "\"\(item.displayName)\" is not movable"
            case .eventOperationTimeout:
                "Event operation timed out for \"\(item.displayName)\""
            case .boundsCheckTimeout:
                "Bounds check timed out for \"\(item.displayName)\""
            case .otherTimeout:
                "Operation timed out for \"\(item.displayName)\""
            }
        }

        /// Description of the error for debugging purposes.
        var description: String {
            var parameters = [String]()
            parameters.append("code: \(code.logString)")
            parameters.append("item: \(item.logString)")
            return "\(Self.self)(\(parameters.joined(separator: ", ")))"
        }

        /// Description of the error for display purposes.
        var errorDescription: String? {
            message
        }

        /// Suggestion for recovery from the error.
        var recoverySuggestion: String? {
            "Please try again. If the error persists, please file a bug report."
        }
    }
}

// MARK: - Async Waiters

extension MenuBarItemManager {
    /// Use this to pad out event operations, if needed.
    ///
    /// - Parameter duration: The duration to wait. Defaults to 20ms.
    private func eventSleep(for duration: Duration = .milliseconds(20)) async {
        try? await Task.sleep(for: duration)
    }

    /// Waits asynchronously for the given operation to complete.
    ///
    /// - Parameters:
    ///   - timeout: Amount of time to wait before throwing an error.
    ///   - operation: The operation to perform.
    private func waitWithTask(
        timeout: Duration?,
        @_inheritActorContext @_implicitSelfCapture
        operation: sending @escaping @isolated(any) () async throws -> Void
    ) async throws {
        let task = if let timeout {
            Task(timeout: timeout, operation: operation)
        } else {
            Task(operation: operation)
        }
        try await task.value
    }

    /// Waits asynchronously for the mouse to stop moving.
    ///
    /// - Parameter timeout: Amount of time to wait before throwing an error.
    private func waitForMouseToStopMoving(timeout: Duration? = nil) async throws {
        let duration = Duration.milliseconds(100)
        guard MouseEvents.lastMovementOccurred(within: duration) else {
            return
        }
        try await waitWithTask(timeout: timeout) {
            while true {
                try Task.checkCancellation()
                if !MouseEvents.lastMovementOccurred(within: duration) {
                    break
                }
                try await Task.sleep(for: duration)
            }
        }
    }

    /// Waits asynchronously until all mouse buttons are up.
    ///
    /// - Parameter timeout: Amount of time to wait before throwing an error.
    private func waitForAllMouseButtonsUp(timeout: Duration? = nil) async throws {
        guard MouseEvents.isButtonPressed() else {
            return
        }
        try await waitWithTask(timeout: timeout) {
            var cancellable: AnyCancellable?

            await withCheckedContinuation { continuation in
                let mask: NSEvent.EventTypeMask = [.leftMouseUp, .rightMouseUp, .otherMouseUp]
                cancellable = RunLoopLocalEventMonitor.publisher(for: mask, mode: .eventTracking)
                    .merge(with: UniversalEventMonitor.publisher(for: mask))
                    .removeDuplicates()
                    .combineLatest(Timer.publish(every: 0.5, on: .main, in: .common).autoconnect())
                    .sink { _ in
                        if MouseEvents.isButtonPressed() {
                            return
                        }
                        cancellable?.cancel()
                        continuation.resume()
                    }
            }
        }
    }

    /// Waits asynchronously until all modifier keys are up.
    ///
    /// - Parameter timeout: Amount of time to wait before throwing an error.
    private func waitForAllModifierKeysUp(timeout: Duration? = nil) async throws {
        if NSEvent.modifierFlags.isEmpty {
            return
        }
        try await waitWithTask(timeout: timeout) {
            var cancellable: AnyCancellable?

            await withCheckedContinuation { continuation in
                let mask: NSEvent.EventTypeMask = .flagsChanged
                cancellable = RunLoopLocalEventMonitor.publisher(for: mask, mode: .eventTracking)
                    .merge(with: UniversalEventMonitor.publisher(for: mask))
                    .removeDuplicates()
                    .combineLatest(Timer.publish(every: 0.5, on: .main, in: .common).autoconnect())
                    .sink { _ in
                        guard NSEvent.modifierFlags.isEmpty else {
                            return
                        }
                        cancellable?.cancel()
                        continuation.resume()
                    }
            }
        }
    }
}

// MARK: - Move Items

extension MenuBarItemManager {
    /// Destinations for menu bar item move operations.
    enum MoveDestination {
        /// Specifies a destination left of the given target item.
        case leftOfItem(MenuBarItem)
        /// Specifies a destination right of the given target item.
        case rightOfItem(MenuBarItem)

        /// A string to use for logging purposes.
        var logString: String {
            switch self {
            case .leftOfItem(let item): "left of \(item.logString)"
            case .rightOfItem(let item): "right of \(item.logString)"
            }
        }
    }

    /// Returns the current bounds for the given item.
    ///
    /// - Parameter item: The item to return the current bounds for.
    private func getCurrentBounds(for item: MenuBarItem) -> CGRect? {
        guard let bounds = Bridging.getWindowBounds(for: item.windowID) else {
            logger.error("Couldn't get current bounds for \(item.logString, privacy: .public)")
            return nil
        }
        return bounds
    }

    /// Returns the end point for moving an item to the given destination.
    ///
    /// - Parameter destination: The destination to return the end point for.
    private func getEndPoint(for destination: MoveDestination) throws -> CGPoint {
        switch destination {
        case .leftOfItem(let targetItem):
            guard let currentBounds = getCurrentBounds(for: targetItem) else {
                throw EventError(code: .invalidItem, item: targetItem)
            }
            return CGPoint(x: currentBounds.minX, y: currentBounds.midY)
        case .rightOfItem(let targetItem):
            guard let currentBounds = getCurrentBounds(for: targetItem) else {
                throw EventError(code: .invalidItem, item: targetItem)
            }
            return CGPoint(x: currentBounds.maxX, y: currentBounds.midY)
        }
    }

    /// Returns the fallback point for returning the given item to its original
    /// position if a move fails.
    ///
    /// - Parameter item: The item to return the fallback point for.
    private func getFallbackPoint(for item: MenuBarItem) throws -> CGPoint {
        guard let currentBounds = getCurrentBounds(for: item) else {
            throw EventError(code: .invalidItem, item: item)
        }
        return CGPoint(x: currentBounds.midX, y: currentBounds.midY)
    }

    /// Returns the target item for the given destination.
    ///
    /// - Parameter destination: The destination to get the target item from.
    private func getTargetItem(for destination: MoveDestination) -> MenuBarItem {
        switch destination {
        case .leftOfItem(let targetItem), .rightOfItem(let targetItem): targetItem
        }
    }

    /// Returns a Boolean value that indicates whether the given item is in the
    /// correct position for the given destination.
    ///
    /// - Parameters:
    ///   - item: The item to check the position of.
    ///   - destination: The destination to compare the item's position against.
    private func itemHasCorrectPosition(item: MenuBarItem, for destination: MoveDestination) throws -> Bool {
        guard let currentBounds = getCurrentBounds(for: item) else {
            throw EventError(code: .invalidItem, item: item)
        }
        switch destination {
        case .leftOfItem(let targetItem):
            guard let currentTargetBounds = getCurrentBounds(for: targetItem) else {
                throw EventError(code: .invalidItem, item: targetItem)
            }
            return currentBounds.maxX == currentTargetBounds.minX
        case .rightOfItem(let targetItem):
            guard let currentTargetBounds = getCurrentBounds(for: targetItem) else {
                throw EventError(code: .invalidItem, item: targetItem)
            }
            return currentBounds.minX == currentTargetBounds.maxX
        }
    }

    /// Returns a Boolean value that indicates whether the given events have the
    /// same values for each integer value field.
    ///
    /// - Parameters:
    ///   - events: The events to compare.
    ///   - integerFields: An array of integer value fields to compare on each event.
    private nonisolated func eventsMatch(_ events: [CGEvent], by integerFields: [CGEventField]) -> Bool {
        var fieldValues = Set<[Int64]>()
        for event in events {
            let values = integerFields.map(event.getIntegerValueField)
            fieldValues.insert(values)
            if fieldValues.count != 1 {
                return false
            }
        }
        return true
    }

    /// Posts an event to the given event tap location.
    ///
    /// - Parameters:
    ///   - event: The event to post.
    ///   - location: The event tap location to post the event to.
    private nonisolated func postEvent(_ event: CGEvent, to location: EventTap.Location) {
        logger.debug(
            """
            Posting \(event.type.logString, privacy: .public) \
            to \(location.logString, privacy: .public)
            """
        )
        switch location {
        case .hidEventTap: event.post(tap: .cghidEventTap)
        case .sessionEventTap: event.post(tap: .cgSessionEventTap)
        case .annotatedSessionEventTap: event.post(tap: .cgAnnotatedSessionEventTap)
        case .pid(let pid): event.postToPid(pid)
        }
    }

    /// Posts an event to the given event tap location and waits until it is
    /// received before returning.
    ///
    /// - Parameters:
    ///   - event: The event to post.
    ///   - location: The event tap location to post the event to.
    ///   - item: The menu bar item that the event affects.
    private func postEventAndWaitToReceive(
        _ event: CGEvent,
        to location: EventTap.Location,
        item: MenuBarItem
    ) async throws {
        return try await withCheckedThrowingContinuation { continuation in
            let eventTap = EventTap(
                options: .listenOnly,
                location: location,
                place: .tailAppendEventTap,
                types: [event.type]
            ) { [weak self] proxy, type, rEvent in
                guard let self else {
                    proxy.disable()
                    return nil
                }

                // Reenable the tap if disabled by the system.
                if type == .tapDisabledByUserInput || type == .tapDisabledByTimeout {
                    proxy.enable()
                    return nil
                }

                // Verify that the received event was the sent event.
                guard eventsMatch([rEvent, event], by: CGEventField.menuBarItemEventFields) else {
                    return nil
                }

                // Ensure the tap is enabled, preventing multiple calls to resume().
                guard proxy.isEnabled else {
                    logger.debug(
                        """
                        Event tap \"\(proxy.label, privacy: .public)\" is disabled \
                        (item: \(item.logString, privacy: .public))
                        """
                    )
                    return nil
                }

                logger.debug(
                    """
                    Received \(type.logString, privacy: .public) \
                    at \(location.logString, privacy: .public) \
                    (item: \(item.logString, privacy: .public))
                    """
                )

                // Disable the tap and resume the continuation.
                proxy.disable()
                continuation.resume()

                return nil
            }

            eventTap.enable(timeout: .milliseconds(100)) { [logger] in
                logger.error(
                    """
                    Event tap \"\(eventTap.label, privacy: .public)\" timed out \
                    (item: \(item.logString, privacy: .public))
                    """
                )
                eventTap.disable()
                continuation.resume(throwing: EventError(code: .eventOperationTimeout, item: item))
            }

            // Post the event to the location.
            postEvent(event, to: location)
        }
    }

    /// Does a lot of weird magic to make a menu bar item receive an event.
    ///
    /// - Parameters:
    ///   - event: The event to send.
    ///   - firstLocation: The first location to send the event to.
    ///   - secondLocation: The second location to send the event to.
    ///   - item: The menu bar item that the event affects.
    private func scrombleEvent(
        _ event: CGEvent,
        from firstLocation: EventTap.Location,
        to secondLocation: EventTap.Location,
        item: MenuBarItem
    ) async throws {
        // Create a null event and assign it unique user data.
        guard let nullEvent = CGEvent(source: nil) else {
            throw EventError(code: .eventCreationFailure, item: item)
        }
        let nullUserData = Int64(truncatingIfNeeded: Int(bitPattern: ObjectIdentifier(nullEvent)))
        nullEvent.setIntegerValueField(.eventSourceUserData, value: nullUserData)

        return try await withCheckedThrowingContinuation { continuation in
            // Create an event tap for the null event at the first location.
            // This tap throws away all events it receives.
            let eventTap1 = EventTap(
                label: "EventTap 1",
                options: .defaultTap,
                location: firstLocation,
                place: .tailAppendEventTap,
                types: [nullEvent.type]
            ) { [weak self] proxy, type, rEvent in
                guard let self else {
                    proxy.disable()
                    return nil
                }

                // Reenable the tap if disabled by the system.
                if type == .tapDisabledByUserInput || type == .tapDisabledByTimeout {
                    proxy.enable()
                    return nil
                }

                // Verify that this is the null event.
                guard rEvent.getIntegerValueField(.eventSourceUserData) == nullUserData else {
                    return nil
                }

                // Disable the tap and post the real event to the second location.
                proxy.disable()
                postEvent(event, to: secondLocation)

                return nil
            }

            // Create an event tap for the real event at the second location.
            // This tap can listen for events, but cannot alter or discard them.
            let eventTap2 = EventTap(
                label: "EventTap 2",
                options: .listenOnly,
                location: secondLocation,
                place: .tailAppendEventTap,
                types: [event.type]
            ) { [weak self] proxy, type, rEvent in
                guard let self else {
                    proxy.disable()
                    return nil
                }

                // Reenable the tap if disabled by the system.
                if type == .tapDisabledByUserInput || type == .tapDisabledByTimeout {
                    proxy.enable()
                    return nil
                }

                // Verify that the received event was the sent event.
                guard eventsMatch([rEvent, event], by: CGEventField.menuBarItemEventFields) else {
                    return nil
                }

                // Ensure the tap is enabled, preventing multiple calls to resume().
                guard proxy.isEnabled else {
                    logger.debug(
                        """
                        Event tap \"\(proxy.label, privacy: .public)\" is disabled \
                        (item: \(item.logString, privacy: .public))
                        """
                    )
                    return nil
                }

                // Disable the tap, post the event to the first location, and resume
                // the continuation.
                proxy.disable()
                postEvent(event, to: firstLocation)
                continuation.resume()

                return nil
            }

            // Enable both taps, with a timeout on the second tap.
            eventTap1.enable()
            eventTap2.enable(timeout: .milliseconds(100)) { [logger] in
                logger.error(
                    """
                    Event tap \"\(eventTap2.label, privacy: .public)\" timed out \
                    (item: \(item.logString, privacy: .public))
                    """
                )
                eventTap1.disable()
                eventTap2.disable()
                continuation.resume(throwing: EventError(code: .eventOperationTimeout, item: item))
            }

            // Post the null event to the first location.
            postEvent(nullEvent, to: firstLocation)
        }
    }

    /// Does a lot of weird magic to make a menu bar item receive an event, then
    /// waits for the bounds of the given menu bar item to change before returning.
    ///
    /// - Parameters:
    ///   - event: The event to send.
    ///   - firstLocation: The first location to send the event to.
    ///   - secondLocation: The second location to send the event to.
    ///   - item: The item whose bounds should be observed.
    private func scrombleEvent(
        _ event: CGEvent,
        from firstLocation: EventTap.Location,
        to secondLocation: EventTap.Location,
        waitingForBoundsChangeOf item: MenuBarItem
    ) async throws {
        guard let currentBounds = getCurrentBounds(for: item) else {
            try await scrombleEvent(event, from: firstLocation, to: secondLocation, item: item)
            logger.warning(
                """
                Couldn't get bounds for \(item.logString, privacy: .public), \
                so using fixed delay
                """
            )
            // This will be slow, but subsequent events will have a better chance of succeeding.
            try await Task.sleep(for: .milliseconds(100))
            return
        }
        try await scrombleEvent(event, from: firstLocation, to: secondLocation, item: item)
        try await waitForBoundsChange(of: item, initialBounds: currentBounds, timeout: .milliseconds(100))
    }

    /// Waits for a menu bar item's bounds to change from an initial value.
    ///
    /// - Parameters:
    ///   - item: The item whose bounds should be observed.
    ///   - initialBounds: An initial value to compare the item's bounds against.
    ///   - timeout: The amount of time to wait before throwing a timeout error.
    private func waitForBoundsChange(of item: MenuBarItem, initialBounds: CGRect, timeout: Duration) async throws {
        struct BoundsCheckCancellationError: Error { }

        let boundsCheckTask = Task(timeout: timeout) {
            while true {
                try Task.checkCancellation()
                guard let currentBounds = getCurrentBounds(for: item) else {
                    throw BoundsCheckCancellationError()
                }
                if currentBounds != initialBounds {
                    logger.debug(
                        """
                        Bounds for \(item.logString, privacy: .public) changed \
                        to \(NSStringFromRect(currentBounds), privacy: .public)
                        """
                    )
                    return
                }
            }
        }
        do {
            try await boundsCheckTask.value
        } catch is BoundsCheckCancellationError {
            logger.warning(
                """
                Bounds check for \(item.logString, privacy: .public) \
                was cancelled, so using fixed delay
                """
            )
            // This will be slow, but subsequent events will have a better chance of succeeding.
            try await Task.sleep(for: .milliseconds(100))
        } catch is TaskTimeoutError {
            throw EventError(code: .boundsCheckTimeout, item: item)
        }
    }

    /// Permits all events for an event source during the given suppression states,
    /// suppressing local events for the given interval.
    private func permitAllEvents(
        for stateID: CGEventSourceStateID,
        during states: [CGEventSuppressionState],
        suppressionInterval: TimeInterval,
        item: MenuBarItem
    ) throws {
        guard let source = CGEventSource(stateID: stateID) else {
            throw EventError(code: .invalidEventSource, item: item)
        }
        for state in states {
            source.setLocalEventsFilterDuringSuppressionState(.permitAllEvents, state: state)
        }
        source.localEventsSuppressionInterval = suppressionInterval
    }

    /// Tries to wake up the given item if it is not responding to events.
    private func wakeUpItem(_ item: MenuBarItem) async throws {
        logger.debug("Attempting to wake up \(item.logString, privacy: .public)")

        guard let source = CGEventSource(stateID: .hidSystemState) else {
            throw EventError(code: .invalidEventSource, item: item)
        }
        guard let currentBounds = getCurrentBounds(for: item) else {
            throw EventError(code: .invalidItem, item: item)
        }

        let wakePoint = CGPoint(x: currentBounds.midX, y: currentBounds.midY)

        guard
            let mouseDownEvent = CGEvent.menuBarItemEvent(
                type: .move(.leftMouseDown),
                location: wakePoint,
                item: item,
                pid: item.ownerPID,
                source: source
            ),
            let mouseUpEvent = CGEvent.menuBarItemEvent(
                type: .move(.leftMouseUp),
                location: wakePoint,
                item: item,
                pid: item.ownerPID,
                source: source
            )
        else {
            throw EventError(code: .eventCreationFailure, item: item)
        }

        let eventTask = Task {
            try await scrombleEvent(
                mouseDownEvent,
                from: .pid(item.ownerPID),
                to: .sessionEventTap,
                item: item
            )
            try await scrombleEvent(
                mouseUpEvent,
                from: .pid(item.ownerPID),
                to: .sessionEventTap,
                item: item
            )
        }
        let result = await eventTask.result
        await eventSleep()
        try result.get()
    }

    /// Moves a menu bar item to the given destination, without restoring the mouse
    /// pointer to its initial location.
    ///
    /// - Parameters:
    ///   - item: A menu bar item to move.
    ///   - destination: A destination to move the menu bar item.
    private func moveItemWithoutRestoringMouseLocation(_ item: MenuBarItem, to destination: MoveDestination) async throws {
        guard item.isMovable else {
            throw EventError(code: .notMovable, item: item)
        }
        guard let source = CGEventSource(stateID: .hidSystemState) else {
            throw EventError(code: .invalidEventSource, item: item)
        }

        let startPoint = CGPoint(x: 20_000, y: 20_000)
        let endPoint = try getEndPoint(for: destination)
        let fallbackPoint = try getFallbackPoint(for: item)
        let targetItem = getTargetItem(for: destination)

        guard
            let mouseDownEvent = CGEvent.menuBarItemEvent(
                type: .move(.leftMouseDown),
                location: startPoint,
                item: item,
                pid: item.ownerPID,
                source: source
            ),
            let mouseUpEvent = CGEvent.menuBarItemEvent(
                type: .move(.leftMouseUp),
                location: endPoint,
                item: targetItem,
                pid: item.ownerPID,
                source: source
            ),
            let fallbackEvent = CGEvent.menuBarItemEvent(
                type: .move(.leftMouseUp),
                location: fallbackPoint,
                item: item,
                pid: item.ownerPID,
                source: source
            )
        else {
            throw EventError(code: .eventCreationFailure, item: item)
        }

        try permitAllEvents(
            for: .combinedSessionState,
            during: [
                .eventSuppressionStateRemoteMouseDrag,
                .eventSuppressionStateSuppressionInterval,
            ],
            suppressionInterval: 0,
            item: item
        )

        lastItemMoveStartDate = .now

        do {
            try await scrombleEvent(
                mouseDownEvent,
                from: .pid(item.ownerPID),
                to: .sessionEventTap,
                waitingForBoundsChangeOf: item
            )
            try await scrombleEvent(
                mouseUpEvent,
                from: .pid(item.ownerPID),
                to: .sessionEventTap,
                waitingForBoundsChangeOf: item
            )
        } catch {
            do {
                let eventTask = Task {
                    logger.debug(
                        """
                        Posting fallback event for moving \
                        \(item.logString, privacy: .public)
                        """
                    )
                    try await postEventAndWaitToReceive(
                        fallbackEvent,
                        to: .sessionEventTap,
                        item: item
                    )
                }

                let result = await eventTask.result
                await eventSleep()

                // Catch this for logging purposes only -- we still want
                // to throw the existing error if the fallback fails.
                try result.get()
            } catch {
                logger.error(
                    """
                    Failed to post fallback event for moving \
                    \(item.logString, privacy: .public)
                    """
                )
            }

            throw error
        }
    }

    /// Moves a menu bar item to the given destination.
    ///
    /// - Parameters:
    ///   - item: A menu bar item to move.
    ///   - destination: A destination to move the menu bar item.
    func move(item: MenuBarItem, to destination: MoveDestination) async throws {
        if try itemHasCorrectPosition(item: item, for: destination) {
            logger.debug(
                """
                \(item.logString, privacy: .public) is already in \
                the correct position
                """
            )
            return
        }

        do {
            // FIXME: Running these checks sequentially like this is prone to error.
            //
            // For example, say the user is holding down a modifier key while moving
            // their mouse - they release the modifier, continue moving their mouse,
            // then press the modifier again. We would completely miss this, as the
            // modifier check would already be finished. We'd have the same problem
            // running the checks concurrently.
            //
            // We need a way to cooperatively restart each check as needed.
            try await waitForAllModifierKeysUp()
            try await waitForMouseToStopMoving()
            try await waitForAllMouseButtonsUp()
        } catch {
            throw EventError(code: .couldNotComplete, item: item)
        }

        logger.info(
            """
            Moving \(item.logString, privacy: .public) to \
            \(destination.logString, privacy: .public)
            """
        )

        guard let appState else {
            throw EventError(code: .invalidAppState, item: item)
        }
        guard let cursorLocation = MouseCursor.locationCoreGraphics else {
            throw EventError(code: .invalidCursorLocation, item: item)
        }
        guard let initialBounds = getCurrentBounds(for: item) else {
            throw EventError(code: .invalidItem, item: item)
        }

        appState.eventManager.stopAll()
        defer {
            appState.eventManager.startAll()
        }

        MouseCursor.hide()

        defer {
            MouseCursor.warp(to: cursorLocation)
            MouseCursor.show()
        }

        // Item movement can occasionally fail. Retry up to a total of 5 attempts,
        // throwing the last attempt's error if it fails.
        for n in 1...5 {
            do {
                try await moveItemWithoutRestoringMouseLocation(item, to: destination)
                guard let newBounds = getCurrentBounds(for: item) else {
                    throw EventError(code: .invalidItem, item: item)
                }
                if newBounds != initialBounds {
                    logger.info("Successfully moved item")
                    break
                } else {
                    throw EventError(code: .couldNotComplete, item: item)
                }
            } catch where n < 5 {
                logger.warning(
                    """
                    Item movement attempt \(n, privacy: .public) \
                    failed with error: \(error, privacy: .public)
                    """
                )
                try await wakeUpItem(item)
                logger.info("Retrying move of item")
                continue
            }
        }
    }

    /// Moves a menu bar item to the given destination and waits until the move
    /// completes before returning.
    /// 
    /// - Parameters:
    ///   - item: A menu bar item to move.
    ///   - destination: A destination to move the menu bar item.
    ///   - timeout: Amount of time to wait before throwing an error.
    func slowMove(item: MenuBarItem, to destination: MoveDestination, timeout: Duration = .seconds(1)) async throws {
        do {
            try await move(item: item, to: destination)
        } catch {
            await eventSleep()
            throw error
        }

        let waitTask = Task(timeout: timeout) {
            while true {
                try Task.checkCancellation()
                if try itemHasCorrectPosition(item: item, for: destination) {
                    return
                }
            }
        }

        do {
            try await waitTask.value
        } catch is TaskTimeoutError {
            throw EventError(code: .otherTimeout, item: item)
        }
    }
}

// MARK: - Click Items

extension MenuBarItemManager {
    /// Clicks the given menu bar item with the given mouse button.
    func click(item: MenuBarItem, with mouseButton: CGMouseButton) async throws {
        guard let source = CGEventSource(stateID: .hidSystemState) else {
            throw EventError(code: .invalidEventSource, item: item)
        }
        guard let cursorLocation = MouseCursor.locationCoreGraphics else {
            throw EventError(code: .invalidCursorLocation, item: item)
        }
        guard let currentBounds = getCurrentBounds(for: item) else {
            throw EventError(code: .invalidItem, item: item)
        }

        let buttonStates = mouseButton.buttonStates
        let clickPoint = currentBounds.center

        guard
            let mouseDownEvent = CGEvent.menuBarItemEvent(
                type: .click(buttonStates.down),
                location: clickPoint,
                item: item,
                pid: item.ownerPID,
                source: source
            ),
            let mouseUpEvent = CGEvent.menuBarItemEvent(
                type: .click(buttonStates.up),
                location: clickPoint,
                item: item,
                pid: item.ownerPID,
                source: source
            ),
            let fallbackEvent = CGEvent.menuBarItemEvent(
                type: .click(buttonStates.up),
                location: clickPoint,
                item: item,
                pid: item.ownerPID,
                source: source
            )
        else {
            throw EventError(code: .eventCreationFailure, item: item)
        }

        try permitAllEvents(
            for: .combinedSessionState,
            during: [
                .eventSuppressionStateRemoteMouseDrag,
                .eventSuppressionStateSuppressionInterval,
            ],
            suppressionInterval: 0,
            item: item
        )

        MouseCursor.hide()

        defer {
            MouseCursor.warp(to: cursorLocation)
            MouseCursor.show()
        }

        do {
            logger.info(
                """
                Clicking \(item.logString, privacy: .public) with \
                \(mouseButton.logString, privacy: .public)
                """
            )
            await eventSleep()
            try await scrombleEvent(mouseDownEvent, from: .pid(item.ownerPID), to: .sessionEventTap, item: item)
            await eventSleep()
            try await scrombleEvent(mouseUpEvent, from: .pid(item.ownerPID), to: .sessionEventTap, item: item)
            await eventSleep()
        } catch {
            do {
                let eventTask = Task {
                    logger.debug(
                        """
                        Posting fallback event for clicking \
                        \(item.logString, privacy: .public)
                        """
                    )
                    try await postEventAndWaitToReceive(
                        fallbackEvent,
                        to: .sessionEventTap,
                        item: item
                    )
                }

                let result = await eventTask.result
                await eventSleep()

                // Catch this for logging purposes only -- we still want
                // to throw the existing error if the fallback fails.
                try result.get()
            } catch {
                logger.error(
                    """
                    Failed to post fallback event for clicking \
                    \(item.logString, privacy: .public)
                    """
                )
            }
            throw error
        }
    }
}

// MARK: - Temporarily Show Items

extension MenuBarItemManager {
    /// Gets the destination to return the given item to after it is temporarily shown.
    private func getReturnDestination(for item: MenuBarItem, in items: [MenuBarItem]) -> MoveDestination? {
        if let index = items.firstIndex(matching: item.tag) {
            if items.indices.contains(index + 1) {
                return .leftOfItem(items[index + 1])
            } else if items.indices.contains(index - 1) {
                return .rightOfItem(items[index - 1])
            }
        }
        return nil
    }

    /// Schedules a timer for the given interval, attempting to rehide the current
    /// temporarily shown items when the timer fires.
    private func runTempShownItemTimer(for interval: TimeInterval) {
        logger.debug(
            """
            Running rehide timer for temporarily shown items \
            with interval: \(interval, privacy: .public)
            """
        )
        tempShownItemsTimer?.invalidate()
        tempShownItemsTimer = .scheduledTimer(withTimeInterval: interval, repeats: false) { [weak self] timer in
            guard let self else {
                timer.invalidate()
                return
            }
            logger.debug("Rehide timer fired")
            Task {
                await self.rehideTempShownItems()
            }
        }
    }

    /// Temporarily shows the given item.
    ///
    /// The item is cached alongside a destination that it will be automatically returned
    /// to. If `true` is passed to the `clickWhenFinished` parameter, the item is clicked
    /// once movement is finished.
    ///
    /// - Parameters:
    ///   - item: An item to show.
    ///   - clickWhenFinished: A Boolean value that indicates whether the item should be
    ///     clicked once movement is finished.
    ///   - mouseButton: The mouse button of the click.
    func tempShowItem(_ item: MenuBarItem, clickWhenFinished: Bool, mouseButton: CGMouseButton) {
        guard let screen = NSScreen.main else {
            return
        }

        let displayID = screen.displayID

        if Bridging.isWindowOnDisplay(item.windowID, displayID) {
            if clickWhenFinished {
                Task {
                    do {
                        try await click(item: item, with: mouseButton)
                    } catch {
                        logger.error("ERROR: \(error, privacy: .public)")
                    }
                }
            }
            return
        }

        guard
            let appState,
            let applicationMenuFrame = appState.menuBarManager.getApplicationMenuFrame(for: displayID)
        else {
            logger.warning(
                """
                No application menu frame, so not showing \
                \(item.logString, privacy: .public)
                """
            )
            return
        }

        logger.info("Temporarily showing \(item.logString, privacy: .public)")

        var items = MenuBarItem.getMenuBarItems(option: .activeSpace)

        guard let destination = getReturnDestination(for: item, in: items) else {
            logger.warning("No return destination for \(item.logString, privacy: .public)")
            return
        }

        // Remove all items up to the hidden control item.
        items.trimPrefix { $0.tag != .hiddenControlItem }
        // Remove the hidden control item.
        items.removeFirst()

        // Remove all offscreen items.
        if #available(macOS 26.0, *) {
            // TODO: isOnScreen doesn't work properly as of macOS 26 Developer Beta 1. Remove this if/when it works again.
            items.trimPrefix { !Bridging.isWindowOnDisplay($0.windowID, displayID) }
        } else {
            items.trimPrefix { !$0.isOnScreen }
        }

        let maxX = if let rightArea = screen.auxiliaryTopRightArea {
            max(rightArea.minX + 20, applicationMenuFrame.maxX)
        } else {
            applicationMenuFrame.maxX
        }

        // Remove items until we have enough room to show this item.
        items.trimPrefix { $0.bounds.minX - item.bounds.width <= maxX }

        guard let targetItem = items.first else {
            let alert = NSAlert()
            alert.messageText = "Not enough room to show \"\(item.displayName)\""
            alert.runModal()
            return
        }

        let contextTask = Task {
            try await slowMove(item: item, to: .leftOfItem(targetItem))
            await eventSleep()

            let context: TempShownItemContext

            if clickWhenFinished {
                let beforeWindows = WindowInfo.getWindows(option: .onScreen)

                await eventSleep()
                try await click(item: item, with: mouseButton)
                await eventSleep(for: .seconds(0.25))

                let afterWindows = WindowInfo.getWindows(option: .onScreen)

                let shownInterfaceWindow = afterWindows.first { afterWindow in
                    afterWindow.ownerPID == item.sourcePID &&
                    !beforeWindows.contains { beforeWindow in
                        afterWindow.windowID == beforeWindow.windowID
                    }
                }

                context = TempShownItemContext(
                    tag: item.tag,
                    returnDestination: destination,
                    shownInterfaceWindow: shownInterfaceWindow
                )
            } else {
                context = TempShownItemContext(
                    tag: item.tag,
                    returnDestination: destination,
                    shownInterfaceWindow: nil
                )
            }

            return context
        }

        Task {
            do {
                let context = try await contextTask.value
                tempShownItemContexts.append(context)
                runTempShownItemTimer(for: appState.settings.advanced.tempShowInterval)
            } catch {
                logger.error("ERROR: \(error, privacy: .public)")
            }
        }
    }

    /// Rehides all temporarily shown items.
    ///
    /// If an item is currently showing its interface, this method waits for the
    /// interface to close before hiding the items.
    func rehideTempShownItems() async {
        guard !tempShownItemContexts.isEmpty else {
            return
        }

        guard !MouseEvents.isButtonPressed() else {
            logger.debug("Mouse button is down, so waiting to rehide")
            runTempShownItemTimer(for: 3)
            return
        }
        guard !tempShownItemContexts.contains(where: { $0.isShowingInterface }) else {
            logger.debug("Menu bar item interface is shown, so waiting to rehide")
            runTempShownItemTimer(for: 3)
            return
        }

        logger.info("Rehiding temporarily shown items")

        var failedContexts = [TempShownItemContext]()

        let items = MenuBarItem.getMenuBarItems(option: .activeSpace)

        while let context = tempShownItemContexts.popLast() {
            guard let item = items.first(where: { $0.tag == context.tag }) else {
                continue
            }
            do {
                try await slowMove(item: item, to: context.returnDestination)
            } catch {
                logger.error(
                    """
                    Failed to rehide \(item.logString, privacy: .public) \
                    (error: \(error, privacy: .public))
                    """
                )
                failedContexts.append(context)
            }
            await eventSleep()
        }

        if failedContexts.isEmpty {
            tempShownItemsTimer?.invalidate()
            tempShownItemsTimer = nil
        } else {
            tempShownItemContexts = failedContexts
            logger.warning("Some items failed to rehide")
            runTempShownItemTimer(for: 3)
        }
    }

    /// Removes a temporarily shown item from the cache.
    ///
    /// This ensures that the item will _not_ be returned to its previous location.
    func removeTempShownItemFromCache(with tag: MenuBarItemTag) {
        tempShownItemContexts.removeAll { $0.tag == tag }
    }
}

// MARK: - Control Item Order

extension MenuBarItemManager {
    /// Enforces the order of the given control items, ensuring that the always-hidden
    /// control item stays to the left of the hidden control item.
    private func enforceControlItemOrder(controlItems: ControlItemSet) async {
        let hidden = controlItems.hidden

        guard
            let alwaysHidden = controlItems.alwaysHidden,
            hidden.bounds.maxX <= alwaysHidden.bounds.minX
        else {
            return
        }

        logger.info("Control items incorrectly ordered, enforcing correct order")

        do {
            try await slowMove(item: alwaysHidden, to: .leftOfItem(hidden))
        } catch {
            logger.error("Error enforcing control item order: \(error, privacy: .public)")
        }
    }
}

// MARK: - Menu Bar Item Event Helper Types

/// Button states for menu bar item events.
private enum MenuBarItemEventButtonState {
    case leftMouseDown
    case leftMouseUp
    case rightMouseDown
    case rightMouseUp
    case otherMouseDown
    case otherMouseUp
}

/// Event types for menu bar item events.
private enum MenuBarItemEventType {
    /// The event type for moving a menu bar item.
    case move(MenuBarItemEventButtonState)

    /// The event type for clicking a menu bar item.
    case click(MenuBarItemEventButtonState)

    /// The button state of this event type.
    var buttonState: MenuBarItemEventButtonState {
        switch self {
        case .move(let state), .click(let state): state
        }
    }

    /// This event type's equivalent CGEventType.
    var cgEventType: CGEventType {
        switch buttonState {
        case .leftMouseDown: .leftMouseDown
        case .leftMouseUp: .leftMouseUp
        case .rightMouseDown: .rightMouseDown
        case .rightMouseUp: .rightMouseUp
        case .otherMouseDown: .otherMouseDown
        case .otherMouseUp: .otherMouseUp
        }
    }

    /// The event flags for this event type.
    var cgEventFlags: CGEventFlags {
        switch self {
        case .move(.leftMouseDown): .maskCommand
        case .move, .click: []
        }
    }

    /// The mouse button for this event type.
    var mouseButton: CGMouseButton {
        switch buttonState {
        case .leftMouseDown, .leftMouseUp: .left
        case .rightMouseDown, .rightMouseUp: .right
        case .otherMouseDown, .otherMouseUp: .center
        }
    }
}

// MARK: - CGEventField Helpers

private extension CGEventField {
    /// Key to access a field that contains the event's window identifier.
    static let windowID = CGEventField(rawValue: 0x33)! // swiftlint:disable:this force_unwrapping

    /// An array of integer fields that are required for a menu bar item event.
    static let menuBarItemRequiredWindowFields: [CGEventField] = [
        .mouseEventWindowUnderMousePointer,
        .mouseEventWindowUnderMousePointerThatCanHandleThisEvent,
    ]

    /// An array of integer fields that may be set for a menu bar item event.
    static let menuBarItemOptionalWindowFields: [CGEventField] = [.windowID]

    /// An array of integer event fields that can be used to compare menu bar item events.
    static let menuBarItemEventFields: [CGEventField] = {
        let baseFields: [CGEventField] = [.eventSourceUserData]
        return baseFields + menuBarItemRequiredWindowFields + menuBarItemOptionalWindowFields
    }()
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

    /// The equivalent down and up button states for menu bar item click events.
    var buttonStates: (down: MenuBarItemEventButtonState, up: MenuBarItemEventButtonState) {
        switch self {
        case .left: (.leftMouseDown, .leftMouseUp)
        case .right: (.rightMouseDown, .rightMouseUp)
        default: (.otherMouseDown, .otherMouseUp)
        }
    }
}

// MARK: - CGEvent Constructor

private extension CGEvent {
    /// Returns an event that can be sent to a menu bar item.
    ///
    /// - Parameters:
    ///   - type: The type of the event.
    ///   - location: The location of the event. Does not need to be
    ///     within the bounds of the item.
    ///   - item: The target item of the event.
    ///   - pid: The target process identifier of the event. Does not
    ///     need to be the item's `ownerPID`.
    ///   - source: The source of the event.
    class func menuBarItemEvent(
        type: MenuBarItemEventType,
        location: CGPoint,
        item: MenuBarItem,
        pid: pid_t,
        source: CGEventSource
    ) -> CGEvent? {
        guard let event = CGEvent(
            mouseEventSource: source,
            mouseType: type.cgEventType,
            mouseCursorPosition: location,
            mouseButton: type.mouseButton
        ) else {
            return nil
        }
        event.setFlags(for: type)
        event.setTargetPID(pid)
        event.setUserData(ObjectIdentifier(event))
        event.setWindowID(item.windowID, for: type)
        event.setClickState(for: type)
        return event
    }

    private func setFlags(for type: MenuBarItemEventType) {
        flags = type.cgEventFlags
    }

    private func setTargetPID(_ pid: pid_t) {
        let targetPID = Int64(pid)
        setIntegerValueField(.eventTargetUnixProcessID, value: targetPID)
    }

    private func setUserData(_ bitPattern: ObjectIdentifier) {
        let userData = Int64(Int(bitPattern: bitPattern))
        setIntegerValueField(.eventSourceUserData, value: userData)
    }

    private func setWindowID(_ windowID: CGWindowID, for type: MenuBarItemEventType) {
        let windowID = Int64(windowID)

        for field in CGEventField.menuBarItemRequiredWindowFields {
            setIntegerValueField(field, value: windowID)
        }

        if case .move = type {
            setIntegerValueField(.windowID, value: windowID)
        }
    }

    private func setClickState(for type: MenuBarItemEventType) {
        guard case .click = type else {
            return
        }
        setIntegerValueField(.mouseEventClickState, value: 1)
    }
}
