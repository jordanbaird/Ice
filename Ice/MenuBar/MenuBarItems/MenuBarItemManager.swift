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
    /// An actor that manages menu bar item cache operations.
    private final actor CacheActor {
        private var cacheTask: Task<Void, Never>?

        /// Runs the given async closure as a task and waits for it
        /// to complete before returning.
        func runCacheTask(_ operation: @escaping () async -> Void) async {
            cacheTask?.cancel()
            cacheTask = Task(operation: operation)
            await cacheTask?.value
        }
    }

    /// The manager's menu bar item cache.
    @Published private(set) var itemCache = ItemCache(displayID: nil)

    /// Logger for the menu bar item manager.
    private let logger = Logger(category: "MenuBarItemManager")

    /// Serial queue for posting events directly to menu bar items.
    private let scrombleQueue = DispatchQueue.targetingGlobal(
        label: "MenuBarItemManager.scrombleQueue",
        qos: .userInteractive
    )

    /// An actor that manages menu bar item cache operations.
    private let cacheActor = CacheActor()

    /// Cached window identifiers for the most recent menu
    /// bar items.
    private var cachedItemWindowIDs = [CGWindowID]()

    /// Context values for the current temporarily shown menu
    /// bar items.
    private var tempShownItemContexts = [TempShownItemContext]()

    /// A timer for rehiding temporarily shown menu bar items.
    private var rehideTimer: Timer?

    /// A timestamp taken at the start of the latest menu bar
    /// item movement operation.
    private var latestMoveOperationTimestamp: ContinuousClock.Instant?

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

    /// Returns a Boolean value that indicates whether the latest menu bar
    /// item movement operation was started within the given time duration.
    func latestMoveOperationStarted(within duration: Duration) -> Bool {
        guard let timestamp = latestMoveOperationTimestamp else {
            return false
        }
        return timestamp.duration(to: .now) <= duration
    }
}

// MARK: - Item Cache

extension MenuBarItemManager {
    /// Cache for menu bar items.
    struct ItemCache: Hashable {
        /// All cached menu bar items, keyed by section.
        private var storage = [MenuBarSection.Name: [MenuBarItem]]()

        /// The identifier of the display with the active menu bar at
        /// the time this cache was created.
        let displayID: CGDirectDisplayID?

        /// The cached menu bar items as an array.
        var managedItems: [MenuBarItem] {
            MenuBarSection.Name.allCases.reduce(into: []) { result, section in
                result.append(contentsOf: managedItems(for: section))
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
                index = (index - 1).clamped(to: range)
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
        var tempShownItems = [(MenuBarItem, MoveDestination)]()

        private(set) lazy var hiddenControlItemBounds = bestBounds(for: controlItems.hidden)
        private(set) lazy var alwaysHiddenControlItemBounds = controlItems.alwaysHidden.map(bestBounds)

        init(controlItems: ControlItemPair, displayID: CGDirectDisplayID?) {
            self.controlItems = controlItems
            self.cache = ItemCache(displayID: displayID)
        }

        func bestBounds(for item: MenuBarItem) -> CGRect {
            MenuBarItem.currentBounds(for: item) ?? item.bounds
        }

        func isValidForCaching(_ item: MenuBarItem) -> Bool {
            // Filter out non-hideable items and the two separator control items.
            item.canBeHidden && (!item.isControlItem || item.tag == .visibleControlItem)
        }

        mutating func isItemInSection(_ item: MenuBarItem, _ section: MenuBarSection.Name) -> Bool {
            lazy var itemBounds = bestBounds(for: item)
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

    /// Caches the given menu bar items, without ensuring that the control
    /// items are in the correct order.
    private func uncheckedCacheItems(items: [MenuBarItem], context: CacheContext) {
        var context = context

        outer: for item in items where context.isValidForCaching(item) {
            if let temp = tempShownItemContexts.first(where: { $0.tag == item.tag }) {
                // Cache temporarily shown items as if they were in their original locations.
                // Keep track of them separately and use their return destinations to insert
                // them into the cache once all other items have been handled.
                context.tempShownItems.append((item, temp.returnDestination))
                continue
            }

            for section in MenuBarSection.Name.allCases where context.isItemInSection(item, section) {
                context.cache[section].append(item)
                continue outer
            }

            logger.warning("\(item.logString, privacy: .public) was not cached")
            cachedItemWindowIDs.removeAll() // Make sure we don't skip the next cache attempt.
        }

        for (item, destination) in context.tempShownItems {
            context.cache.insert(item, at: destination)
        }

        itemCache = context.cache
        logger.debug("Updated menu bar item cache")
    }

    /// Caches the current menu bar items, regardless of the current item
    /// state, ensuring that the control items are in the correct order.
    func cacheItemsRegardless(_ currentItemWindowIDs: [CGWindowID]? = nil) async {
        await cacheActor.runCacheTask { [weak self] in
            guard let self else {
                return
            }

            let displayID = Bridging.getActiveMenuBarDisplayID()
            var items = await MenuBarItem.getMenuBarItems(option: .activeSpace)

            cachedItemWindowIDs = currentItemWindowIDs ?? items.reversed().map { $0.windowID }

            guard let controlItems = ControlItemPair(items: &items) else {
                // ???: Is clearing the cache the best thing to do here?
                logger.warning("Missing control item for hidden section - clearing menu bar item cache")
                itemCache = ItemCache(displayID: nil)
                return
            }

            await enforceControlItemOrder(controlItems: controlItems)
            uncheckedCacheItems(items: items, context: CacheContext(controlItems: controlItems, displayID: displayID))
        }
    }

    /// Caches the current menu bar items if needed, ensuring that the
    /// control items are in the correct order.
    func cacheItemsIfNeeded() async {
        guard !latestMoveOperationStarted(within: .seconds(1)) else {
            logger.debug("Skipping menu bar item cache due to recent item movement")
            return
        }

        let itemWindowIDs = Bridging.getMenuBarWindowList(option: [.itemsOnly, .activeSpace])

        if
            cachedItemWindowIDs == itemWindowIDs,
            itemCache.managedItems.allSatisfy({ $0.sourcePID != nil })
        {
            return
        }

        await cacheItemsRegardless(itemWindowIDs)
    }
}

// MARK: - Async Waiters

extension MenuBarItemManager {
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
                    .merge(with: EventMonitor.publish(events: mask, scope: .universal))
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
                    .merge(with: EventMonitor.publish(events: mask, scope: .universal))
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

// MARK: - Event Helpers

extension MenuBarItemManager {
    /// An error that can occur during menu bar item event operations.
    struct EventError: Error, CustomStringConvertible, LocalizedError {
        /// Error codes within the domain of menu bar item event errors.
        enum ErrorCode: Int, CustomStringConvertible {
            /// A menu bar item bounds check timed out.
            case boundsCheckTimeout
            /// An operation could not be completed.
            case couldNotComplete
            /// The creation of a menu bar item event failed.
            case eventCreationFailure
            /// A menu bar item event operation timed out.
            case eventOperationTimeout
            /// The shared app state is invalid or could not be found.
            case invalidAppState
            /// An event source could not be created or is otherwise invalid.
            case invalidEventSource
            /// A menu bar item is invalid.
            case invalidItem
            /// A menu bar item's current bounds could not be found.
            case missingCurrentBounds
            /// The location of the mouse could not be found.
            case missingMouseLocation
            /// A menu bar item cannot be moved.
            case notMovable
            /// An operation timed out.
            case otherTimeout

            /// Description of the code for debugging purposes.
            var description: String {
                switch self {
                case .boundsCheckTimeout: "boundsCheckTimeout"
                case .couldNotComplete: "couldNotComplete"
                case .eventCreationFailure: "eventCreationFailure"
                case .eventOperationTimeout: "eventOperationTimeout"
                case .invalidAppState: "invalidAppState"
                case .invalidEventSource: "invalidEventSource"
                case .invalidItem: "invalidItem"
                case .missingCurrentBounds: "missingCurrentBounds"
                case .missingMouseLocation: "missingMouseLocation"
                case .notMovable: "notMovable"
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
            case .boundsCheckTimeout:
                #"Bounds check timed out for "\#(item.displayName)""#
            case .couldNotComplete:
                #"Could not complete event operation for "\#(item.displayName)""#
            case .eventCreationFailure:
                #"Failed to create event for "\#(item.displayName)""#
            case .eventOperationTimeout:
                #"Event operation timed out for "\#(item.displayName)""#
            case .invalidAppState:
                #"Invalid app state for "\#(item.displayName)""#
            case .invalidEventSource:
                #"Invalid event source for "\#(item.displayName)""#
            case .invalidItem:
                #""\#(item.displayName)" is invalid"#
            case .missingCurrentBounds:
                #"Missing current bounds for "\#(item.displayName)""#
            case .missingMouseLocation:
                #"Missing mouse location for "\#(item.displayName)""#
            case .notMovable:
                #""\#(item.displayName)" is not movable"#
            case .otherTimeout:
                #"Operation timed out for "\#(item.displayName)""#
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

    /// Waits for the given duration. Use this to pad out event
    /// operations when needed.
    ///
    /// - Parameter duration: The duration to wait.
    private func eventSleep(for duration: Duration = .milliseconds(20)) async {
        try? await Task.sleep(for: duration)
    }

    /// Returns the current bounds for the given item.
    private func getCurrentBounds(for item: MenuBarItem) throws -> CGRect {
        guard let bounds = MenuBarItem.currentBounds(for: item) else {
            throw EventError(code: .missingCurrentBounds, item: item)
        }
        return bounds
    }

    /// Returns the event source for moving a menu bar item.
    private func getEventSource(item: MenuBarItem) throws -> CGEventSource {
        enum Context {
            static var source: CGEventSource?
        }
        if let source = Context.source {
            return source
        }
        guard let source = CGEventSource(stateID: .hidSystemState) else {
            throw EventError(code: .invalidEventSource, item: item)
        }
        Context.source = source
        return source
    }

    /// Returns the current mouse location.
    private func getMouseLocation(item: MenuBarItem) throws -> CGPoint {
        guard let location = MouseCursor.locationCoreGraphics else {
            throw EventError(code: .missingMouseLocation, item: item)
        }
        return location
    }

    /// Permits all events for an event source during the given suppression
    /// states, suppressing local events for the given interval.
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
        logger.debug("Posting \(event.type.logString, privacy: .public) to \(location.logString, privacy: .public)")
        switch location {
        case .hidEventTap: event.post(tap: .cghidEventTap)
        case .sessionEventTap: event.post(tap: .cgSessionEventTap)
        case .annotatedSessionEventTap: event.post(tap: .cgAnnotatedSessionEventTap)
        case .pid(let pid): event.postToPid(pid)
        }
    }

    /// Posts an event to the given event tap location and waits
    /// until it is received before returning.
    ///
    /// - Parameters:
    ///   - event: The event to post.
    ///   - location: The event tap location to post the event to.
    ///   - item: The menu bar item that the event targets.
    ///   - timeout: The duration to wait before throwing an error.
    private func postEventRoundtrip(
        _ event: CGEvent,
        to location: EventTap.Location,
        item: MenuBarItem,
        timeout: Duration
    ) async throws {
        var eventTap: EventTap?

        let timeoutTask = Task(timeout: timeout) {
            try await withCheckedThrowingContinuation { continuation in
                eventTap = EventTap(
                    options: .listenOnly,
                    location: location,
                    placement: .tailAppendEventTap,
                    type: event.type,
                    callbackQueue: scrombleQueue
                ) { [weak self] tap, rEvent in
                    guard let self else {
                        tap.disable()
                        return rEvent
                    }

                    guard eventsMatch([rEvent, event], by: CGEventField.menuBarItemEventFields) else {
                        return rEvent
                    }

                    tap.disable()
                    continuation.resume()

                    return rEvent
                }

                eventTap?.enable()

                postEvent(event, to: location)
            }
        }

        do {
            try await timeoutTask.value
        } catch is TaskTimeoutError {
            throw EventError(code: .eventOperationTimeout, item: item)
        } catch {
            throw EventError(code: .couldNotComplete, item: item)
        }
    }

    /// Does a lot of weird magic to make a menu bar item receive
    /// an event.
    ///
    /// - Parameters:
    ///   - event: The event to post.
    ///   - firstLocation: The first location to post the event.
    ///   - secondLocation: The second location to post the event.
    ///   - item: The menu bar item that the event targets.
    ///   - timeout: The duration to wait before throwing an error.
    private func scrombleEvent(
        _ event: CGEvent,
        from firstLocation: EventTap.Location,
        to secondLocation: EventTap.Location,
        item: MenuBarItem,
        timeout: Duration
    ) async throws {
        guard let nullEvent = CGEvent.uniqueNullEvent() else {
            throw EventError(code: .eventCreationFailure, item: item)
        }

        var eventTap1: EventTap?
        var eventTap2: EventTap?

        let timeoutTask = Task(timeout: timeout) {
            await withCheckedContinuation { continuation in
                // Create an event tap for the null event at the first location.
                // Once this tap receives the event, it posts the real event to
                // the second location and discards the null event.
                eventTap1 = EventTap(
                    label: "EventTap 1",
                    options: .defaultTap,
                    location: firstLocation,
                    placement: .headInsertEventTap,
                    type: nullEvent.type,
                    callbackQueue: scrombleQueue
                ) { [weak self] tap, rEvent in
                    guard let self else {
                        tap.disable()
                        return rEvent
                    }

                    guard eventsMatch([rEvent, nullEvent], by: [.eventSourceUserData]) else {
                        return rEvent
                    }

                    tap.disable()
                    postEvent(event, to: secondLocation)

                    return nil
                }

                // Create an event tap for the real event at the second location.
                // Once this tap receives the event, it resumes the continuation.
                eventTap2 = EventTap(
                    label: "EventTap 2",
                    options: .listenOnly,
                    location: secondLocation,
                    placement: .tailAppendEventTap,
                    type: event.type,
                    callbackQueue: scrombleQueue
                ) { [weak self] tap, rEvent in
                    guard let self else {
                        tap.disable()
                        return rEvent
                    }

                    guard eventsMatch([rEvent, event], by: CGEventField.menuBarItemEventFields) else {
                        return rEvent
                    }

                    tap.disable()
                    continuation.resume()

                    return rEvent
                }

                eventTap1?.enable()
                eventTap2?.enable()

                // Post the null event to the first location.
                postEvent(nullEvent, to: firstLocation)
            }
        }

        do {
            try await timeoutTask.value
        } catch is TaskTimeoutError {
            throw EventError(code: .eventOperationTimeout, item: item)
        } catch {
            throw EventError(code: .couldNotComplete, item: item)
        }
    }
}

// MARK: - Move Operations

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

    /// Returns the end location for moving an item to the given destination.
    private func getEndLocation(for destination: MoveDestination) throws -> CGPoint {
        let bounds = try getCurrentBounds(for: destination.targetItem)
        return switch destination {
        case .leftOfItem: CGPoint(x: bounds.minX, y: bounds.midY)
        case .rightOfItem: CGPoint(x: bounds.maxX, y: bounds.midY)
        }
    }

    /// Returns a Boolean value that indicates whether the given item is
    /// in the correct position for the given destination.
    private func itemHasCorrectPosition(item: MenuBarItem, for destination: MoveDestination) throws -> Bool {
        let itemBounds = try getCurrentBounds(for: item)
        let targetBounds = try getCurrentBounds(for: destination.targetItem)
        return switch destination {
        case .leftOfItem: itemBounds.maxX == targetBounds.minX
        case .rightOfItem: itemBounds.minX == targetBounds.maxX
        }
    }

    /// Actions to perform after an event is received.
    enum ScrombleEventDeferredAction {
        struct BoundsChangeOptions: OptionSet {
            let rawValue: Int

            static let ignoreErrors = BoundsChangeOptions(rawValue: 1 << 0)
            static let sleepOnError = BoundsChangeOptions(rawValue: 1 << 1)
        }

        case waitForBoundsChange(options: BoundsChangeOptions = [])

        func createTask(
            with item: MenuBarItem,
            timeout: Duration,
            manager: MenuBarItemManager
        ) async -> () async throws -> Void {
            switch self {
            case .waitForBoundsChange(let options):
                let boundsResult = await Task {
                    try await manager.getCurrentBounds(for: item)
                }.result
                return {
                    do {
                        let bounds = try boundsResult.get()
                        try await manager.waitForBoundsChange(
                            of: item,
                            initialBounds: bounds,
                            timeout: timeout
                        )
                    } catch {
                        manager.logger.warning("Bounds check failed with error: \(error, privacy: .public)")
                        if options.contains(.sleepOnError) {
                            await manager.eventSleep(for: .milliseconds(100))
                        }
                        if options.contains(.ignoreErrors) {
                            return
                        }
                        throw error
                    }
                }
            }
        }
    }

    /// Does a lot of weird magic to make a menu bar item receive
    /// an event, then performs the given action.
    /// 
    /// - Parameters:
    ///   - event: The event to post.
    ///   - firstLocation: The first location to post the event.
    ///   - secondLocation: The second location to post the event.
    ///   - item: The menu bar item that the event targets.
    ///   - timeout: The duration to wait before throwing an error.
    ///   - deferredAction: An action to perform after the event is
    ///     received.
    private func scrombleEvent(
        _ event: CGEvent,
        from firstLocation: EventTap.Location,
        to secondLocation: EventTap.Location,
        item: MenuBarItem,
        timeout: Duration,
        deferredAction: ScrombleEventDeferredAction
    ) async throws {
        let deferredTask = await deferredAction.createTask(with: item, timeout: timeout, manager: self)
        try await scrombleEvent(event, from: firstLocation, to: secondLocation, item: item, timeout: timeout)
        try await deferredTask()
    }

    /// Waits for a menu bar item's bounds to change from an initial value.
    ///
    /// - Parameters:
    ///   - item: The menu bar item to check for bounds changes.
    ///   - initialBounds: An initial value to determine whether the item's
    ///     bounds have changed.
    ///   - timeout: The duration to wait before throwing an error.
    private func waitForBoundsChange(
        of item: MenuBarItem,
        initialBounds: CGRect,
        timeout: Duration
    ) async throws {
        let boundsCheckTask = Task(timeout: timeout) {
            while true {
                try Task.checkCancellation()
                let currentBounds = try getCurrentBounds(for: item)
                guard currentBounds != initialBounds else {
                    continue
                }
                logger.debug(
                    """
                    Bounds for \(item.logString, privacy: .public) changed \
                    to \(NSStringFromRect(currentBounds), privacy: .public)
                    """
                )
                return
            }
        }
        do {
            try await boundsCheckTask.value
        } catch let error as EventError {
            throw error
        } catch is TaskTimeoutError {
            throw EventError(code: .boundsCheckTimeout, item: item)
        } catch {
            throw EventError(code: .couldNotComplete, item: item)
        }
    }

    /// Attempts to move a menu bar item to the given destination.
    ///
    /// - Parameters:
    ///   - item: The menu bar item to move.
    ///   - destination: The destination to move the menu bar item.
    ///   - source: The event source used to create the events that
    ///     move the item.
    ///   - timeout: The duration to wait before throwing an error.
    private func performMoveOperation(
        item: MenuBarItem,
        destination: MoveDestination,
        source: CGEventSource,
        timeout: Duration
    ) async throws {
        let pid = item.sourcePID ?? item.ownerPID

        guard
            let moveEvent1 = CGEvent.menuBarItemEvent(
                source: source,
                type: .move(.leftMouseDown),
                location: CGPoint(x: 20_000, y: 20_000),
                item: item,
                pid: pid
            ),
            let moveEvent2 = CGEvent.menuBarItemEvent(
                source: source,
                type: .move(.leftMouseUp),
                location: try getEndLocation(for: destination),
                item: destination.targetItem,
                pid: pid
            ),
            let fallbackEvent = CGEvent.menuBarItemEvent(
                source: source,
                type: .move(.leftMouseUp),
                location: try getCurrentBounds(for: item).center,
                item: item,
                pid: pid
            )
        else {
            throw EventError(code: .eventCreationFailure, item: item)
        }

        latestMoveOperationTimestamp = .now

        do {
            try await scrombleEvent(
                moveEvent1,
                from: .pid(pid),
                to: .sessionEventTap,
                item: item,
                timeout: timeout,
                deferredAction: .waitForBoundsChange(options: [.ignoreErrors, .sleepOnError])
            )
            try await scrombleEvent(
                moveEvent2,
                from: .pid(pid),
                to: .sessionEventTap,
                item: item,
                timeout: timeout,
                deferredAction: .waitForBoundsChange(options: .sleepOnError)
            )
        } catch {
            logger.warning("Move events failed. Posting fallback.")

            // Pad with eventSleep calls to reduce the chance that
            // events are still being processed somewhere.
            await eventSleep()
            do {
                // Catch this for logging purposes only. We want to
                // propagate the original error.
                try await postEventRoundtrip(
                    fallbackEvent,
                    to: .sessionEventTap,
                    item: item,
                    timeout: timeout
                )
            } catch {
                logger.error("Fallback event failed with error: \(error, privacy: .public)")
            }
            await eventSleep()
            throw error
        }
    }

    /// Moves a menu bar item to the given destination.
    ///
    /// - Parameters:
    ///   - item: The menu bar item to move.
    ///   - destination: The destination to move the menu bar item.
    ///   - timeout: The duration to wait before throwing an error.
    func move(
        item: MenuBarItem,
        to destination: MoveDestination,
        timeout: Duration = .milliseconds(100)
    ) async throws {
        guard item.isMovable else {
            throw EventError(code: .notMovable, item: item)
        }
        guard let appState else {
            throw EventError(code: .invalidAppState, item: item)
        }

        guard try !itemHasCorrectPosition(item: item, for: destination) else {
            logger.debug("\(item.logString, privacy: .public) already has correct position")
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

        let source = try getEventSource(item: item)
        let mouseLocation = try getMouseLocation(item: item)

        try permitAllEvents(
            for: .combinedSessionState,
            during: [
                .eventSuppressionStateRemoteMouseDrag,
                .eventSuppressionStateSuppressionInterval,
            ],
            suppressionInterval: 0,
            item: item
        )

        appState.eventManager.stopAll()
        defer {
            appState.eventManager.startAll()
        }

        MouseCursor.hide()

        defer {
            MouseCursor.warp(to: mouseLocation)
            MouseCursor.show()
        }

        logger.debug(
            """
            Moving \(item.logString, privacy: .public) to \
            \(destination.logString, privacy: .public)
            """
        )

        let moveTask = Task {
            // Move operations can occasionally fail. Retry up to a total
            // of 5 attempts, throwing the last attempt's error if it fails.
            for n in 1...5 {
                try Task.checkCancellation()
                do {
                    return try await performMoveOperation(
                        item: item,
                        destination: destination,
                        source: source,
                        timeout: timeout
                    )
                } catch where n < 5 {
                    logger.warning(
                        """
                        Move attempt \(n, privacy: .public) failed with error: \
                        \(error, privacy: .public)
                        """
                    )
                }
            }
        }

        do {
            try await moveTask.value
            logger.debug("Successfully moved item")
        } catch let error as EventError {
            throw error
        } catch {
            throw EventError(code: .couldNotComplete, item: item)
        }
    }

    /// Moves a menu bar item to the given destination and waits until
    /// the move is finished before returning.
    ///
    /// - Parameters:
    ///   - item: The menu bar item to move.
    ///   - destination: The destination to move the menu bar item.
    ///   - timeout: The duration to wait before throwing an error.
    func slowMove(
        item: MenuBarItem,
        to destination: MoveDestination,
        timeout: Duration = .seconds(1)
    ) async throws {
        try await move(item: item, to: destination, timeout: .milliseconds(100))

        let waitTask = Task(timeout: timeout) {
            while try !itemHasCorrectPosition(item: item, for: destination) {
                try Task.checkCancellation()
            }
        }

        do {
            try await waitTask.value
        } catch is TaskTimeoutError {
            throw EventError(code: .otherTimeout, item: item)
        }
    }
}

// MARK: - Click Operations

extension MenuBarItemManager {
    /// Clicks the given menu bar item.
    ///
    /// - Parameters:
    ///   - item: The menu bar item to click.
    ///   - mouseButton: The mouse button to click the item with.
    ///   - timeout: The duration to wait before throwing an error.
    func click(
        item: MenuBarItem,
        with mouseButton: CGMouseButton,
        timeout: Duration = .milliseconds(100)
    ) async throws {
        guard let appState else {
            throw EventError(code: .invalidAppState, item: item)
        }

        let source = try getEventSource(item: item)
        let mouseLocation = try getMouseLocation(item: item)
        let currentBounds = try getCurrentBounds(for: item)

        let buttonStates = mouseButton.buttonStates
        let clickLocation = currentBounds.center
        let pid = item.sourcePID ?? item.ownerPID

        guard
            let clickEvent1 = CGEvent.menuBarItemEvent(
                source: source,
                type: .click(buttonStates.down),
                location: clickLocation,
                item: item,
                pid: pid
            ),
            let clickEvent2 = CGEvent.menuBarItemEvent(
                source: source,
                type: .click(buttonStates.up),
                location: clickLocation,
                item: item,
                pid: pid
            ),
            let fallbackEvent = CGEvent.menuBarItemEvent(
                source: source,
                type: .click(buttonStates.up),
                location: clickLocation,
                item: item,
                pid: pid
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

        appState.eventManager.stopAll()
        defer {
            appState.eventManager.startAll()
        }

        MouseCursor.hide()

        defer {
            MouseCursor.warp(to: mouseLocation)
            MouseCursor.show()
        }

        logger.debug(
            """
            Clicking \(item.logString, privacy: .public) with \
            \(mouseButton.logString, privacy: .public)
            """
        )

        do {
            try await scrombleEvent(
                clickEvent1,
                from: .pid(pid),
                to: .sessionEventTap,
                item: item,
                timeout: timeout
            )
            try await scrombleEvent(
                clickEvent2,
                from: .pid(pid),
                to: .sessionEventTap,
                item: item,
                timeout: timeout
            )
            logger.debug("Successfully clicked item")
        } catch {
            logger.warning("Click events failed. Posting fallback.")

            // Pad with eventSleep calls to reduce the chance that
            // events are still being processed somewhere.
            await eventSleep()
            do {
                // Catch this for logging purposes only. We want to
                // propagate the original error.
                try await postEventRoundtrip(
                    fallbackEvent,
                    to: .sessionEventTap,
                    item: item,
                    timeout: timeout
                )
            } catch {
                logger.error("Fallback event failed with error: \(error, privacy: .public)")
            }
            await eventSleep()
            throw error
        }
    }
}

// MARK: - Temporarily Show

extension MenuBarItemManager {
    /// Context for a temporarily shown menu bar item.
    private struct TempShownItemContext {
        /// The tag associated with the item.
        let tag: MenuBarItemTag

        /// The destination to return the item to.
        let returnDestination: MoveDestination

        /// The window of the item's shown interface.
        let shownInterfaceWindow: WindowInfo?

        /// The number of attempts that have been made to rehide the item.
        var rehideAttempts = 0

        /// A Boolean value that indicates whether the menu bar item's
        /// interface is showing.
        var isShowingInterface: Bool {
            guard
                let shownInterfaceWindow,
                let currentWindow = WindowInfo(windowID: shownInterfaceWindow.windowID)
            else {
                return false
            }
            if
                currentWindow.layer != CGWindowLevelForKey(.popUpMenuWindow),
                let owningApplication = currentWindow.owningApplication
            {
                return owningApplication.isActive && currentWindow.isOnScreen
            } else {
                return currentWindow.isOnScreen
            }
        }
    }

    /// Gets the destination to return the given item to after it is
    /// temporarily shown.
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
                await self.rehideTempShownItems()
            }
        }
    }

    /// Temporarily shows the given item.
    ///
    /// The item is cached and returned to its original destination after the
    /// time interval specified by ``AdvancedSettings/tempShowInterval``.
    ///
    /// - Parameters:
    ///   - item: The item to temporarily show.
    ///   - mouseButton: The mouse button to click the item with.
    func tempShow(item: MenuBarItem, clickingWith mouseButton: CGMouseButton) async {
        guard
            let displayID = Bridging.getActiveMenuBarDisplayID(),
            let screen = NSScreen.screens.first(where: { $0.displayID == displayID })
        else {
            logger.error("No active menu bar display, so not showing \(item.logString, privacy: .public)")
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

        // Remove all items up to the hidden control item.
        items.trimPrefix { $0.tag != .hiddenControlItem }

        if !items.isEmpty {
            // Remove the hidden control item.
            items.removeFirst()
        }

        // Remove all offscreen items.
        if #available(macOS 26.0, *) {
            // MenuBarItem.isOnScreen doesn't work properly as of macOS 26.
            // TODO: Revert this if and when it works again.
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
            logger.warning("Not enough room to show \(item.logString, privacy: .public)")
            let alert = NSAlert()
            alert.messageText = "Not enough room to show \"\(item.displayName)\""
            alert.runModal()
            return
        }

        logger.debug("Temporarily showing \(item.logString, privacy: .public)")

        do {
            try await slowMove(item: item, to: .leftOfItem(targetItem))
        } catch {
            logger.error("Error showing item: \(error, privacy: .public)")
            return
        }

        rehideTimer?.invalidate()
        defer {
            runRehideTimer()
        }

        await eventSleep()

        let idsBeforeClick = Set(Bridging.getWindowList(option: .onScreen))

        do {
            try await click(item: item, with: mouseButton)
        } catch {
            logger.error("Error clicking item: \(error, privacy: .public)")
            let context = TempShownItemContext(
                tag: item.tag,
                returnDestination: destination,
                shownInterfaceWindow: nil
            )
            tempShownItemContexts.append(context)
            return
        }

        await eventSleep(for: .seconds(0.5))

        let windowsAfterClick = WindowInfo.createWindows(option: .onScreen)

        let window = windowsAfterClick.first { window in
            window.ownerPID == item.sourcePID && !idsBeforeClick.contains(window.windowID)
        }

        let context = TempShownItemContext(
            tag: item.tag,
            returnDestination: destination,
            shownInterfaceWindow: window
        )
        tempShownItemContexts.append(context)
    }

    /// Rehides all temporarily shown items.
    ///
    /// If an item is currently showing its interface, this method waits
    /// for the interface to close before hiding the items.
    func rehideTempShownItems() async {
        guard !tempShownItemContexts.isEmpty else {
            return
        }

        guard !tempShownItemContexts.contains(where: { $0.isShowingInterface }) else {
            logger.debug("Menu bar item interface is shown, so waiting to rehide")
            runRehideTimer(for: 3)
            return
        }

        let items = await MenuBarItem.getMenuBarItems(option: .activeSpace)
        var failedContexts = [TempShownItemContext]()

        logger.debug("Rehiding temporarily shown items")

        while var context = tempShownItemContexts.popLast() {
            guard let item = items.first(where: { $0.tag == context.tag }) else {
                continue
            }
            do {
                try await slowMove(item: item, to: context.returnDestination)
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
                    tempShownItemContexts.append(context) // Try again.
                } else {
                    // Failed contexts are ultimately added back into the array
                    // of temp shown contexts and rehidden after a longer delay,
                    // so reset the attempt count.
                    context.rehideAttempts = 0
                    failedContexts.append(context)
                }
            }
            await eventSleep()
        }

        if failedContexts.isEmpty {
            rehideTimer?.invalidate()
            rehideTimer = nil
        } else {
            failedContexts.reverse() // Reverse for correct order.
            tempShownItemContexts = failedContexts
            logger.error(
                """
                Some items failed to rehide: \
                \(failedContexts.map { $0.tag }, privacy: .public)
                """
            )
            runRehideTimer(for: 3)
        }
    }

    /// Removes a temporarily shown item from the cache.
    ///
    /// This ensures that the item will _not_ be returned to its
    /// previous location.
    func removeTempShownItemFromCache(with tag: MenuBarItemTag) {
        tempShownItemContexts.removeAll { $0.tag == tag }
    }
}

// MARK: - Enforce Control Item Order

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
            try await slowMove(item: alwaysHidden, to: .leftOfItem(hidden))
        } catch {
            logger.error("Error enforcing control item order: \(error, privacy: .public)")
        }
    }
}

// MARK: - Helper Types

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

// MARK: - CGEvent Helpers

private extension CGEvent {
    /// Returns an event that can be sent to a menu bar item.
    ///
    /// - Parameters:
    ///   - source: The source of the event.
    ///   - type: The type of the event.
    ///   - location: The location of the event. Does not need to be
    ///     within the bounds of the item.
    ///   - item: The target item of the event.
    ///   - pid: The target process identifier of the event. Does not
    ///     need to be the item's `ownerPID`.
    static func menuBarItemEvent(
        source: CGEventSource,
        type: MenuBarItemEventType,
        location: CGPoint,
        item: MenuBarItem,
        pid: pid_t
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

    /// Returns a null event with unique user data.
    static func uniqueNullEvent() -> CGEvent? {
        guard let event = CGEvent(source: nil) else {
            return nil
        }
        event.setUserData(ObjectIdentifier(event))
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
