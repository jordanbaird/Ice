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

    /// Actor for managing menu bar item cache operations.
    private let cacheActor = CacheActor()

    /// Window identifiers for the most recently cached menu bar items.
    private var cachedItemWindowIDs = [CGWindowID]()

    /// Contexts for temporarily shown menu bar items.
    private var temporarilyShownItemContexts = [TemporarilyShownItemContext]()

    /// A timer for rehiding temporarily shown menu bar items.
    private var rehideTimer: Timer?

    /// A timestamp representing the start of the most recent menu
    /// bar item move operation.
    private var latestMoveOperationTimestamp: ContinuousClock.Instant?

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
    /// item move operation was started within the given time duration.
    func latestMoveOperationStarted(within duration: Duration) -> Bool {
        guard let timestamp = latestMoveOperationTimestamp else {
            return false
        }
        return timestamp.duration(to: .now) <= duration
    }
}

// MARK: - Item Cache

extension MenuBarItemManager {
    /// An actor that manages menu bar item cache operations.
    private final actor CacheActor {
        private var cacheTask: Task<Void, Never>?

        /// Runs the given async closure as a task and waits for it to
        /// complete before returning.
        ///
        /// If a task from a previous call to this method is currently
        /// running, that task is cancelled and replaced.
        func runCacheTask(_ operation: @escaping () async -> Void) async {
            cacheTask?.cancel()
            cacheTask = Task(operation: operation)
            await cacheTask?.value
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
            MenuBarItem.currentBounds(for: item) ?? item.bounds
        }

        func isValidForCaching(_ item: MenuBarItem) -> Bool {
            if !item.canBeHidden {
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
    ) {
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
            cachedItemWindowIDs.removeAll() // Make sure we don't skip the next cache attempt.
        }

        itemCache = context.cache
        logger.debug("Updated menu bar item cache")
    }

    /// Caches the current menu bar items regardless of the current item
    /// state, ensuring that the control items are correctly ordered.
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
            uncheckedCacheItems(items: items, controlItems: controlItems, displayID: displayID)
        }
    }

    /// Caches the current menu bar items if needed, ensuring that the
    /// control items are correctly ordered.
    func cacheItemsIfNeeded() async {
        guard !latestMoveOperationStarted(within: .seconds(1)) else {
            logger.debug("Skipping menu bar item cache due to recent item movement")
            return
        }

        let itemWindowIDs = Bridging.getMenuBarWindowList(option: [.itemsOnly, .activeSpace])

        guard cachedItemWindowIDs != itemWindowIDs else {
            return
        }

        await cacheItemsRegardless(itemWindowIDs)
    }
}

// MARK: - User Input Checks

extension MenuBarItemManager {
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
    ///
    /// - Parameter timeout: The duration to wait before throwing an error.
    private nonisolated func waitForUserToPauseInput(timeout: Duration = .seconds(30)) async throws {
        let duration = Duration.milliseconds(100)
        if hasUserPausedInput(for: duration) {
            return
        }
        let waitTask = Task(timeout: timeout) {
            while true {
                try Task.checkCancellation()
                if hasUserPausedInput(for: duration) {
                    break
                }
                try await Task.sleep(for: duration * 2)
            }
        }
        try await waitTask.value
    }
}

// MARK: - Event Helpers

extension MenuBarItemManager {
    /// An error that can occur during menu bar item event operations.
    struct EventError: Error, CustomStringConvertible, LocalizedError {
        /// Error codes within the domain of menu bar item event errors.
        enum ErrorCode: Int, CustomStringConvertible {
            /// A generic indication of a failure.
            case cannotComplete
            /// A failure during the creation of an event.
            case eventCreationFailure
            /// A timeout during an event operation.
            case eventOperationTimeout
            /// An event source cannot be created or is otherwise invalid.
            case invalidEventSource
            /// A menu bar item is not movable.
            case itemNotMovable
            /// A timeout waiting for a menu bar item to respond to an event.
            case itemResponseTimeout
            /// A menu bar item's bounds cannot be found.
            case missingItemBounds
            /// The location of the mouse cannot be found.
            case missingMouseLocation

            /// Description of the code for debugging purposes.
            var description: String {
                switch self {
                case .cannotComplete: "cannotComplete"
                case .eventCreationFailure: "eventCreationFailure"
                case .eventOperationTimeout: "eventOperationTimeout"
                case .invalidEventSource: "invalidEventSource"
                case .itemNotMovable: "itemNotMovable"
                case .itemResponseTimeout: "itemResponseTimeout"
                case .missingItemBounds: "missingItemBounds"
                case .missingMouseLocation: "missingMouseLocation"
                }
            }

            /// A string to use for logging purposes.
            var logString: String {
                "\(self) (rawValue: \(rawValue))"
            }
        }

        /// The error code associated with the error.
        let code: ErrorCode

        /// The menu bar item associated with the error.
        let item: MenuBarItem

        /// Description of the error for debugging purposes.
        var description: String {
            var parameters = [String]()
            parameters.append("code: \(code.logString)")
            parameters.append("item: \(item.logString)")
            return "\(Self.self)(\(parameters.joined(separator: ", ")))"
        }

        /// Description of the error for display purposes.
        var errorDescription: String? {
            switch code {
            case .cannotComplete:
                #"Operation could not be completed for "\#(item.displayName)""#
            case .eventCreationFailure:
                #"Failed to create event for "\#(item.displayName)""#
            case .eventOperationTimeout:
                #"Timeout sending events to "\#(item.displayName)""#
            case .invalidEventSource:
                #"Invalid event source for "\#(item.displayName)""#
            case .itemNotMovable:
                #""\#(item.displayName)" is not movable"#
            case .itemResponseTimeout:
                #"Timeout waiting for response from "\#(item.displayName)""#
            case .missingItemBounds:
                #"Missing screen bounds for "\#(item.displayName)""#
            case .missingMouseLocation:
                #"Missing mouse location for "\#(item.displayName)""#
            }
        }

        /// Suggestion for recovery from the error.
        var recoverySuggestion: String? {
            "Please try again. If the error persists, please file a bug report."
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
        let task = Task.detached(priority: .userInitiated) {
            guard let bounds = MenuBarItem.currentBounds(for: item) else {
                throw EventError(code: .missingItemBounds, item: item)
            }
            return bounds
        }
        return try await task.value
    }

    /// Returns the current mouse location.
    private nonisolated func getMouseLocation(item: MenuBarItem) throws -> CGPoint {
        guard let location = MouseHelpers.locationCoreGraphics else {
            throw EventError(code: .missingMouseLocation, item: item)
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
        with stateID: CGEventSourceStateID = .hidSystemState,
        for item: MenuBarItem
    ) throws -> CGEventSource {
        enum Context {
            static var cache = [CGEventSourceStateID: CGEventSource]()
        }
        if let source = Context.cache[stateID] {
            return source
        }
        guard let source = CGEventSource(stateID: stateID) else {
            throw EventError(code: .invalidEventSource, item: item)
        }
        Context.cache[stateID] = source
        return source
    }

    /// Permits all events for an event source during the given suppression
    /// states, suppressing local events for the given interval.
    private nonisolated func permitAllEvents(
        for stateID: CGEventSourceStateID,
        during states: [CGEventSuppressionState],
        suppressionInterval: TimeInterval,
        item: MenuBarItem
    ) throws {
        let source = try getEventSource(with: stateID, for: item)
        for state in states {
            source.setLocalEventsFilterDuringSuppressionState(.permitAllEvents, state: state)
        }
        source.localEventsSuppressionInterval = suppressionInterval
    }

    /// Casts forbidden magic to make a menu bar item receive an event.
    ///
    /// - Parameters:
    ///   - event: The event to post.
    ///   - firstLocation: The first event tap location to post the event.
    ///   - secondLocation: The second event tap location to post the event.
    ///   - item: The menu bar item that the event targets.
    ///   - timeout: The base duration to wait before throwing an error. The
    ///     value of this parameter is multiplied by `count` to produce the
    ///     actual timeout duration.
    ///   - count: The number of times to repeat the operation. As it is
    ///     considerably more efficient, prefer increasing this value over
    ///     repeatedly calling `scrombleEvent`.
    private nonisolated func scrombleEvent(
        _ event: CGEvent,
        from firstLocation: EventTap.Location,
        to secondLocation: EventTap.Location,
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
            throw EventError(code: .eventCreationFailure, item: item)
        }

        var counter = count
        var eventTaps = [EventTap]()

        let timeoutTask = Task(timeout: timeout * count) {
            try await withCheckedThrowingContinuation { continuation in
                // Create a tap for the entry and exit events at the first location.
                // On entry, decrement the count and post the real event.
                // On exit, resume the continuation.
                let eventTap1 = EventTap(
                    label: "EventTap 1",
                    type: .null,
                    location: firstLocation,
                    placement: .headInsertEventTap,
                    option: .defaultTap
                ) { tap, rEvent in
                    if rEvent.matches(entryEvent, byIntegerFields: [.eventSourceUserData]) {
                        counter -= 1
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

                // Create a tap for the real event at the second location. If the
                // count has reached zero, post the exit event. Otherwise, repost
                // the entry event to go around again.
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
                    if counter <= 0 {
                        tap.disable()
                        exitEvent.post(to: firstLocation)
                    } else {
                        entryEvent.post(to: firstLocation)
                    }
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
            throw EventError(code: .eventOperationTimeout, item: item)
        } catch {
            throw EventError(code: .cannotComplete, item: item)
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

    /// Returns the timeout for move operations associated with the
    /// given item.
    private func getMoveOperationTimeout(for item: MenuBarItem) -> Duration {
        if let timeout = moveOperationTimeouts[item.tag] {
            return timeout
        }
        if item.isBentoBox {
            // Bento Boxes (i.e. Control Center groups) generally take
            // a little longer to respond.
            return .milliseconds(100)
        }
        return .milliseconds(25)
    }

    /// Updates the timeout for move operations associated with the
    /// given item.
    private func updateMoveOperationTimeout(_ timeout: Duration, for item: MenuBarItem) {
        moveOperationTimeouts[item.tag] = min(timeout, .milliseconds(100))
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
        let responseTask = Task.detached(timeout: timeout) {
            while true {
                try Task.checkCancellation()
                let origin = try await self.getCurrentBounds(for: item).origin
                if origin != initialOrigin {
                    return origin
                }
            }
        }
        do {
            let origin = try await responseTask.value
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
            throw EventError(code: .itemResponseTimeout, item: item)
        } catch {
            throw EventError(code: .cannotComplete, item: item)
        }
    }

    /// Creates and posts a series of events to move a menu bar item
    /// to the given destination.
    ///
    /// - Parameters:
    ///   - item: The menu bar item to move.
    ///   - destination: The destination to move the menu bar item.
    ///   - source: The event source used to create the events.
    ///   - timeout: The duration for each individual operation to wait
    ///     before throwing an error.
    private nonisolated func postMoveEvents(
        item: MenuBarItem,
        destination: MoveDestination,
        source: CGEventSource,
        timeout: Duration
    ) async throws {
        try await eventSemaphore.waitUnlessCancelled()
        defer {
            eventSemaphore.signal()
        }

        var itemOrigin = try await getCurrentBounds(for: item).origin
        let targetPoints = try await getTargetPoints(forMoving: item, to: destination)
        let mouseLocation = try getMouseLocation(item: item)
        let pid = getEventPID(for: item)

        guard
            let moveEvent1 = CGEvent.menuBarItemEvent(
                source: source,
                type: .move(.mouseDown),
                location: targetPoints.start,
                item: item,
                pid: pid
            ),
            let moveEvent2 = CGEvent.menuBarItemEvent(
                source: source,
                type: .move(.mouseUp),
                location: targetPoints.end,
                item: destination.targetItem,
                pid: pid
            )
        else {
            throw EventError(code: .eventCreationFailure, item: item)
        }

        await MainActor.run {
            latestMoveOperationTimestamp = .now
        }

        MouseHelpers.hideCursor()
        defer {
            MouseHelpers.warpCursor(to: mouseLocation)
            MouseHelpers.showCursor()
        }

        do {
            try await scrombleEvent(
                moveEvent1,
                from: .pid(pid),
                to: .sessionEventTap,
                item: item,
                timeout: timeout
            )
            itemOrigin = try await waitForMoveEventResponse(
                from: item,
                initialOrigin: itemOrigin,
                timeout: timeout
            )
            try await scrombleEvent(
                moveEvent2,
                from: .pid(pid),
                to: .sessionEventTap,
                item: item,
                timeout: timeout,
                repeating: 2 // Double mouse up prevents invalid item state.
            )
            itemOrigin = try await waitForMoveEventResponse(
                from: item,
                initialOrigin: itemOrigin,
                timeout: timeout
            )
        } catch {
            do {
                logger.debug("Move events failed, posting fallback")
                try await scrombleEvent(
                    moveEvent2,
                    from: .pid(pid),
                    to: .sessionEventTap,
                    item: item,
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

    /// Moves a menu bar item to the given destination.
    ///
    /// - Parameters:
    ///   - item: The menu bar item to move.
    ///   - destination: The destination to move the item to.
    func move(item: MenuBarItem, to destination: MoveDestination) async throws {
        guard try await !itemHasCorrectPosition(item: item, for: destination) else {
            logger.log("\(item.logString, privacy: .public) already has correct position")
            return
        }
        guard item.isMovable else {
            throw EventError(code: .itemNotMovable, item: item)
        }
        guard let appState else {
            throw EventError(code: .cannotComplete, item: item)
        }

        do {
            try await waitForUserToPauseInput()
        } catch {
            throw EventError(code: .cannotComplete, item: item)
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

        let source = try getEventSource(for: item)
        var timeout = getMoveOperationTimeout(for: item)

        defer {
            updateMoveOperationTimeout(timeout, for: item)
        }

        logger.log(
            """
            Moving \(item.logString, privacy: .public) to \
            \(destination.logString, privacy: .public)
            """
        )

        let maxAttempts = 10

        moveLoop: for n in 1...maxAttempts {
            guard !Task.isCancelled else {
                throw EventError(code: .cannotComplete, item: item)
            }

            attempt: do {
                if try await itemHasCorrectPosition(item: item, for: destination) {
                    logger.debug("Item has correct position")
                    break attempt
                }
                try await postMoveEvents(
                    item: item,
                    destination: destination,
                    source: source,
                    timeout: timeout
                )
                timeout -= timeout / 2
            } catch where n < maxAttempts {
                logger.debug("Attempt \(n, privacy: .public) failed: \(error, privacy: .public)")
                await eventSleep()
                timeout += timeout / 2
                continue moveLoop
            } catch let error as EventError {
                timeout += timeout / 2
                throw error
            } catch {
                timeout += timeout / 2
                throw EventError(code: .cannotComplete, item: item)
            }

            logger.debug("Attempt \(n, privacy: .public) succeeded")
            break moveLoop
        }

        logger.log("Successfully moved \(item.logString, privacy: .public)")
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
    ///   - source: The event source used to create the events.
    ///   - timeout: The duration for each individual operation to wait
    ///     before throwing an error.
    private nonisolated func postClickEvents(
        item: MenuBarItem,
        mouseButton: CGMouseButton,
        source: CGEventSource,
        timeout: Duration
    ) async throws {
        try await eventSemaphore.waitUnlessCancelled()
        defer {
            eventSemaphore.signal()
        }

        let clickPoint = try await getCurrentBounds(for: item).center
        let mouseLocation = try getMouseLocation(item: item)
        let clickTypes = getClickSubtypes(for: mouseButton)
        let pid = getEventPID(for: item)

        guard
            let clickEvent1 = CGEvent.menuBarItemEvent(
                source: source,
                type: .click(clickTypes.down),
                location: clickPoint,
                item: item,
                pid: pid
            ),
            let clickEvent2 = CGEvent.menuBarItemEvent(
                source: source,
                type: .click(clickTypes.up),
                location: clickPoint,
                item: item,
                pid: pid
            )
        else {
            throw EventError(code: .eventCreationFailure, item: item)
        }

        MouseHelpers.hideCursor()
        defer {
            MouseHelpers.warpCursor(to: mouseLocation)
            MouseHelpers.showCursor()
        }

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
                timeout: timeout,
                repeating: 2 // Double mouse up prevents invalid item state.
            )
        } catch {
            do {
                logger.debug("Click events failed, posting fallback")
                try await scrombleEvent(
                    clickEvent2,
                    from: .pid(pid),
                    to: .sessionEventTap,
                    item: item,
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
        guard let appState else {
            throw EventError(code: .cannotComplete, item: item)
        }

        do {
            try await waitForUserToPauseInput()
        } catch {
            throw EventError(code: .cannotComplete, item: item)
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

        let source = try getEventSource(for: item)
        let timeout = Duration.milliseconds(250)

        logger.log(
            """
            Clicking \(item.logString, privacy: .public) with \
            \(mouseButton.logString, privacy: .public)
            """
        )

        try await postClickEvents(
            item: item,
            mouseButton: mouseButton,
            source: source,
            timeout: timeout
        )

        logger.log("Successfully clicked \(item.logString, privacy: .public)")
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
                current.layer != CGWindowLevelForKey(.statusWindow),
                let app = current.owningApplication
            {
                return app.isActive && current.isOnscreen
            }
            return current.isOnscreen
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
            if item.isOnscreen && item.canBeHidden {
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
        guard !temporarilyShownItemContexts.isEmpty else {
            return
        }

        guard !temporarilyShownItemContexts.contains(where: { $0.isShowingInterface }) else {
            logger.debug("Menu bar item interface is shown, so waiting to rehide")
            runRehideTimer(for: 3)
            return
        }

        var currentContexts = temporarilyShownItemContexts
        temporarilyShownItemContexts.removeAll()

        let items = await MenuBarItem.getMenuBarItems(option: .activeSpace)
        var failedContexts = [TemporarilyShownItemContext]()

        logger.debug("Rehiding temporarily shown items")

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
            await eventSleep()
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
    ///   - source: The source of the event.
    ///   - type: The type of the event.
    ///   - location: The location of the event. Does not need to be within
    ///     the bounds of the item.
    ///   - item: The target item of the event.
    ///   - pid: The target process identifier of the event. Does not need
    ///     to be the item's `ownerPID`.
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
            mouseButton: type.cgMouseButton
        ) else {
            return nil
        }
        event.setFlags(for: type)
        event.setUserData(ObjectIdentifier(event))
        event.setTargetPID(pid)
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

    private func setFlags(for type: MenuBarItemEventType) {
        flags = type.cgEventFlags
    }

    private func setUserData(_ bitPattern: ObjectIdentifier) {
        let userData = Int64(Int(bitPattern: bitPattern))
        setIntegerValueField(.eventSourceUserData, value: userData)
    }

    private func setTargetPID(_ pid: pid_t) {
        let targetPID = Int64(pid)
        setIntegerValueField(.eventTargetUnixProcessID, value: targetPID)
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
