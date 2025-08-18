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

    /// Logger for the menu bar item manager.
    private nonisolated var logger: Logger { .menuBarItemManager }

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

    /// Returns a duration derived from the refresh rate of the given screen.
    ///
    /// We use this method to avoid tight loops where traditional observation
    /// isn't supported (sometimes the case with private APIs). Should really
    /// only be used after exhausting all other options.
    private func getSleepDurationFromScreenRefreshRate(screen: NSScreen) -> Duration {
        Duration.seconds(screen.maximumRefreshInterval.clamped(to: 0.01...0.1))
    }
}

// MARK: - Item Cache

extension MenuBarItemManager {
    /// Cache for menu bar items.
    struct ItemCache: Hashable {
        /// All cached menu bar items, keyed by section.
        private var storage = [MenuBarSection.Name: [MenuBarItem]]()

        /// The identifier of the display with the active menu bar at the
        /// time this cache was created.
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
            // Filter out non-hideable items and the two separator control items.
            item.canBeHidden && (!item.isControlItem || item.tag == .visibleControlItem)
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

    /// Caches the given menu bar items, without ensuring that the control
    /// items are in the correct order.
    private func uncheckedCacheItems(items: [MenuBarItem], context: CacheContext) {
        var context = context

        for item in items where context.isValidForCaching(item) {
            if item.sourcePID == nil {
                logger.warning("Missing sourcePID for \(item.logString, privacy: .public)")
                context.shouldClearCachedItemWindowIDs = true
            }

            if let temp = tempShownItemContexts.first(where: { $0.tag == item.tag }) {
                // Cache temporarily shown items as if they were in their original locations.
                // Keep track of them separately and use their return destinations to insert
                // them into the cache once all other items have been handled.
                context.tempShownItems.append((item, temp.returnDestination))
                continue
            }

            if let section = context.findSection(for: item) {
                context.cache[section].append(item)
                continue
            }

            logger.warning("Couldn't find section for caching \(item.logString, privacy: .public)")
            context.shouldClearCachedItemWindowIDs = true
        }

        for (item, destination) in context.tempShownItems {
            context.cache.insert(item, at: destination)
        }

        if context.shouldClearCachedItemWindowIDs {
            logger.info("Clearing cached menu bar item windowIDs")
            cachedItemWindowIDs.removeAll() // Make sure we don't skip the next cache attempt.
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

        guard cachedItemWindowIDs != itemWindowIDs else {
            return
        }

        await cacheItemsRegardless(itemWindowIDs)
    }
}

// MARK: - Async Waiters

extension MenuBarItemManager {
    /// An error that can occur during an asynchronous wait operation.
    private enum WaitOperationError: LocalizedError {
        case timeout
        case missingScreenWithMouse
        case other(any Error)

        var errorDescription: String? {
            switch self {
            case .timeout:
                "Wait operation timed out"
            case .missingScreenWithMouse:
                "Couldn't find screen with mouse"
            case .other(let error):
                "Wait operation failed with error: \(error.localizedDescription)"
            }
        }
    }

    /// Waits asynchronously for the given operation to complete.
    ///
    /// - Parameters:
    ///   - timeout: Amount of time to wait before throwing an error.
    ///   - operation: The operation to perform.
    private func performWaitOperation(
        timeout: Duration?,
        @_inheritActorContext @_implicitSelfCapture
        operation: sending @escaping @isolated(any) () async throws -> Void
    ) async throws {
        let task = if let timeout {
            Task(timeout: timeout, operation: operation)
        } else {
            Task(operation: operation)
        }
        do {
            try await task.value
        } catch let error as WaitOperationError {
            throw error
        } catch is TaskTimeoutError {
            throw WaitOperationError.timeout
        } catch {
            throw WaitOperationError.other(error)
        }
    }

    /// Waits asynchronously for the mouse to stop moving.
    ///
    /// - Parameter timeout: Amount of time to wait before throwing an error.
    private func waitForMouseToStopMoving(timeout: Duration? = nil) async throws {
        guard let screen = NSScreen.screenWithMouse else {
            throw WaitOperationError.missingScreenWithMouse
        }
        let duration = getSleepDurationFromScreenRefreshRate(screen: screen)
        guard MouseHelpers.lastMovementOccurred(within: duration) else {
            return
        }
        try await performWaitOperation(timeout: timeout) {
            while true {
                try Task.checkCancellation()
                if !MouseHelpers.lastMovementOccurred(within: duration) {
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
        guard MouseHelpers.isButtonPressed() else {
            return
        }
        try await performWaitOperation(timeout: timeout) {
            var cancellable: AnyCancellable?

            await withCheckedContinuation { continuation in
                let mask: NSEvent.EventTypeMask = [.leftMouseUp, .rightMouseUp, .otherMouseUp]
                cancellable = RunLoopLocalEventMonitor.publisher(for: mask, mode: .eventTracking)
                    .merge(with: EventMonitor.publish(events: mask, scope: .universal))
                    .removeDuplicates()
                    .combineLatest(Timer.publish(every: 0.5, on: .main, in: .common).autoconnect())
                    .sink { _ in
                        if MouseHelpers.isButtonPressed() {
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
        try await performWaitOperation(timeout: timeout) {
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
            /// A generic indication of a failure.
            case cannotComplete
            /// A failure during the creation of an event.
            case eventCreationFailure
            /// A failure during an event operation.
            case eventOperationFailure
            /// A timeout during an event operation.
            case eventOperationTimeout
            /// A menu bar item has an incorrect position after being moved.
            case incorrectPositionAfterMove
            /// An event source cannot be created or is otherwise invalid.
            case invalidEventSource
            /// A menu bar item is invalid.
            case invalidItem
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
                case .eventOperationFailure: "eventOperationFailure"
                case .eventOperationTimeout: "eventOperationTimeout"
                case .incorrectPositionAfterMove: "incorrectPositionAfterMove"
                case .invalidEventSource: "invalidEventSource"
                case .invalidItem: "invalidItem"
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

        /// The error code of this error.
        let code: ErrorCode

        /// The error's menu bar item.
        let item: MenuBarItem

        /// The message associated with this error.
        var message: String {
            switch code {
            case .cannotComplete:
                #"Operation could not be completed for "\#(item.displayName)""#
            case .eventCreationFailure:
                #"Failed to create event for "\#(item.displayName)""#
            case .eventOperationFailure:
                #"Event operation failed for "\#(item.displayName)""#
            case .eventOperationTimeout:
                #"Event operation timed out for "\#(item.displayName)""#
            case .incorrectPositionAfterMove:
                #""\#(item.displayName)" has an incorrect position after being moved"#
            case .invalidEventSource:
                #"Invalid event source for "\#(item.displayName)""#
            case .invalidItem:
                #""\#(item.displayName)" is invalid"#
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

    /// Waits for the given duration, without throwing an error if cancelled.
    private nonisolated func eventSleep(for duration: Duration = .milliseconds(25)) async {
        try? await Task.sleep(for: duration)
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

    /// Waits for a menu bar item's bounds to change in reaction to
    /// a series of received events.
    ///
    /// - Parameters:
    ///   - item: The item to check for bounds changes.
    ///   - initialBounds: The bounds of the item before any events
    ///     were sent to it.
    ///   - timeout: The duration to wait before throwing an error.
    private nonisolated func waitForResponse(
        from item: MenuBarItem,
        initialBounds: CGRect,
        timeout: Duration
    ) async throws -> CGRect {
        let boundsCheckTask = Task.detached(timeout: timeout) {
            while true {
                try Task.checkCancellation()
                let bounds = try await self.getCurrentBounds(for: item)
                if bounds != initialBounds {
                    return bounds
                }
            }
        }
        do {
            let bounds = try await boundsCheckTask.value
            logger.debug(
                """
                Bounds for \(item.logString, privacy: .public) changed \
                to \(NSStringFromRect(bounds), privacy: .public)
                """
            )
            return bounds
        } catch let error as EventError {
            throw error
        } catch is TaskTimeoutError {
            throw EventError(code: .itemResponseTimeout, item: item)
        } catch {
            throw EventError(code: .cannotComplete, item: item)
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
    private nonisolated func postEventRoundtrip(
        _ event: CGEvent,
        to location: EventTap.Location,
        item: MenuBarItem,
        timeout: Duration
    ) async throws {
        var eventTaps = [EventTap]()
        let timeoutTask = Task(timeout: timeout) {
            try await withCheckedThrowingContinuation { continuation in
                let eventTap = EventTap(
                    type: event.type,
                    location: location,
                    placement: .tailAppendEventTap,
                    option: .listenOnly
                ) { tap, rEvent in
                    if rEvent.matches(event, by: CGEventField.menuBarItemEventFields) {
                        tap.disable()
                        continuation.resume()
                    }
                    return rEvent
                }

                eventTaps.append(eventTap)

                Task {
                    await withTaskCancellationHandler {
                        eventTap.enable()
                        event.post(to: location)
                    } onCancel: {
                        eventTap.disable()
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

    /// Does a lot of weird magic to make a menu bar item receive an event.
    ///
    /// - Parameters:
    ///   - event: The event to post.
    ///   - firstTapLocation: The first event tap location to post the event.
    ///   - secondTapLocation: The second event tap location to post the event.
    ///   - item: The menu bar item that the event targets.
    ///   - timeout: The duration to wait before throwing an error.
    private nonisolated func scrombleEvent(
        _ event: CGEvent,
        from firstTapLocation: EventTap.Location,
        to secondTapLocation: EventTap.Location,
        item: MenuBarItem,
        timeout: Duration
    ) async throws {
        guard
            let entryEvent = CGEvent.uniqueNullEvent(),
            let exitEvent = CGEvent.uniqueNullEvent()
        else {
            throw EventError(code: .eventCreationFailure, item: item)
        }

        var eventTaps = [EventTap]()

        let timeoutTask = Task(timeout: timeout) {
            try await withCheckedThrowingContinuation { continuation in
                // Create a tap for the entry and exit events at the first location.
                // This tap is responsible for posting the actual event to the second
                // location and resuming the continuation.
                let eventTap1 = EventTap(
                    label: "EventTap 1",
                    type: .null,
                    location: firstTapLocation,
                    placement: .headInsertEventTap,
                    option: .defaultTap
                ) { tap, rEvent in
                    if rEvent.matches(entryEvent, by: [.eventSourceUserData]) {
                        event.post(to: secondTapLocation)
                        return nil
                    }
                    if rEvent.matches(exitEvent, by: [.eventSourceUserData]) {
                        tap.disable()
                        continuation.resume()
                        return nil
                    }
                    return rEvent
                }

                // Create a tap for the actual event at the second location. This tap
                // is responsible for posting the exit event to the first location.
                let eventTap2 = EventTap(
                    label: "EventTap 2",
                    type: event.type,
                    location: secondTapLocation,
                    placement: .tailAppendEventTap,
                    option: .listenOnly
                ) { tap, rEvent in
                    if rEvent.matches(event, by: CGEventField.menuBarItemEventFields) {
                        tap.disable()
                        exitEvent.post(to: firstTapLocation)
                    }
                    return rEvent
                }

                eventTaps.append(eventTap1)
                eventTaps.append(eventTap2)

                Task {
                    await withTaskCancellationHandler {
                        eventTap1.enable()
                        eventTap2.enable()
                        entryEvent.post(to: firstTapLocation)
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

//    /// Does a lot of weird magic to make a menu bar item receive an event,
//    /// then waits for the item to respond.
//    ///
//    /// - Parameters:
//    ///   - event: The event to post.
//    ///   - firstTapLocation: The first event tap location to post the event.
//    ///   - secondTapLocation: The second event tap location to post the event.
//    ///   - item: The menu bar item that the event targets.
//    ///   - timeout: The duration for individual operations to wait before
//    ///     throwing an error.
//    private nonisolated func scrombleEvent(
//        _ event: CGEvent,
//        from firstTapLocation: EventTap.Location,
//        to secondTapLocation: EventTap.Location,
//        waitingForResponseFrom item: MenuBarItem,
//        timeout: Duration
//    ) async throws {
//        let initialBounds = try await getCurrentBounds(for: item)
//        try await self.scrombleEvent(
//            event,
//            from: firstTapLocation,
//            to: secondTapLocation,
//            item: item,
//            timeout: timeout
//        )
//        try await self.waitForResponse(
//            from: item,
//            initialBounds: initialBounds,
//            timeout: timeout
//        )
//    }
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

    /// Returns the point for moving an item to the given destination.
    private nonisolated func getTargetPoint(for destination: MoveDestination) async throws -> CGPoint {
        let bounds = try await getCurrentBounds(for: destination.targetItem)
        return switch destination {
        case .leftOfItem: CGPoint(x: bounds.minX, y: bounds.minY)
        case .rightOfItem: CGPoint(x: bounds.maxX, y: bounds.minY)
        }
    }

    /// Returns a Boolean value that indicates whether the given item is
    /// in the correct position for the given destination.
    private nonisolated func itemHasCorrectPosition(item: MenuBarItem, for destination: MoveDestination) async throws -> Bool {
        let itemBounds = try await getCurrentBounds(for: item)
        let targetBounds = try await getCurrentBounds(for: destination.targetItem)
        return switch destination {
        case .leftOfItem: itemBounds.maxX == targetBounds.minX
        case .rightOfItem: itemBounds.minX == targetBounds.maxX
        }
    }

    private nonisolated func getPreflightEndPoint(beforeMoving item: MenuBarItem, to destination: MoveDestination) async throws -> CGPoint {
        let itemBounds = try await getCurrentBounds(for: item)
        let targetBounds = try await getCurrentBounds(for: destination.targetItem)
        if itemBounds.maxX <= targetBounds.minX {
            switch destination {
            case .leftOfItem:
                return CGPoint(x: targetBounds.minX - itemBounds.width, y: itemBounds.minY)
            case .rightOfItem:
                return CGPoint(x: itemBounds.minX + targetBounds.width, y: itemBounds.minY)
            }
        } else {
            switch destination {
            case .leftOfItem:
                return CGPoint(x: targetBounds.minX, y: itemBounds.minY)
            case .rightOfItem:
                return CGPoint(x: targetBounds.maxX, y: itemBounds.minY)
            }
        }
    }

    private nonisolated func validatePosition(afterMoving item: MenuBarItem, preflightPoint: CGPoint) async throws {
        let itemBounds = try await getCurrentBounds(for: item)
        if itemBounds.origin.distance(to: preflightPoint) > 1 {
            throw EventError(code: .incorrectPositionAfterMove, item: item)
        }
    }

    /// Creates and posts a series of events to move a menu bar item to
    /// the given destination.
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
        var itemBounds = try await getCurrentBounds(for: item)
        let targetPoint = try await getTargetPoint(for: destination)
        let pid = getEventPID(for: item)

        guard
            let moveEvent1 = CGEvent.menuBarItemEvent(
                source: source,
                type: .move(.mouseDown),
                location: targetPoint,
                item: item,
                pid: pid
            ),
            let moveEvent2 = CGEvent.menuBarItemEvent(
                source: source,
                type: .move(.mouseUp),
                location: targetPoint,
                item: destination.targetItem,
                pid: pid
            ),
            let fallbackEvent = CGEvent.menuBarItemEvent(
                source: source,
                type: .move(.mouseUp),
                location: targetPoint,
                item: item,
                pid: pid
            )
        else {
            throw EventError(code: .eventCreationFailure, item: item)
        }

        await MainActor.run {
            latestMoveOperationTimestamp = .now
        }

        do {
            try await scrombleEvent(
                moveEvent1,
                from: .pid(pid),
                to: .sessionEventTap,
                item: item,
                timeout: timeout
            )
            itemBounds = try await waitForResponse(
                from: item,
                initialBounds: itemBounds,
                timeout: timeout
            )
            try await withThrowingTaskGroup { group in
                group.addTask {
                    while !Task.isCancelled {
                        try await self.scrombleEvent(
                            moveEvent2,
                            from: .pid(pid),
                            to: .sessionEventTap,
                            item: item,
                            timeout: timeout
                        )
                    }
                }
                group.addTask {
                    itemBounds = try await self.waitForResponse(
                        from: item,
                        initialBounds: itemBounds,
                        timeout: timeout
                    )
                }
                try await group.next()
                group.cancelAll()
            }
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
    ///   - source: The event source used to create the events that move
    ///     the item.
    ///   - timeout: The duration for each individual operation to wait
    ///     before throwing an error.
    private func performMoveOperation(
        item: MenuBarItem,
        destination: MoveDestination,
        source: CGEventSource,
        timeout: Duration
    ) async throws {
        let preflightPoint = try await getPreflightEndPoint(beforeMoving: item, to: destination)
        let mouseLocation = try getMouseLocation(item: item)

        // Move operations can occasionally fail. Retry up to a total
        // of 5 attempts, throwing the last attempt's error if it fails.
        for n in 1...5 {
            try Task.checkCancellation()
            do {
                MouseHelpers.hideCursor()

                defer {
                    MouseHelpers.warpCursor(to: mouseLocation)
                    MouseHelpers.showCursor()
                }

                try await postMoveEvents(
                    item: item,
                    destination: destination,
                    source: source,
                    timeout: timeout
                )
                return try await validatePosition(
                    afterMoving: item,
                    preflightPoint: preflightPoint
                )
            } catch where n < 5 {
                logger.debug(
                    """
                    Move attempt \(n, privacy: .public) failed with error: \
                    \(error, privacy: .public)
                    """
                )
            }
        }
    }

    /// Moves a menu bar item to the given destination and waits until
    /// the move is finished before returning.
    ///
    /// - Parameters:
    ///   - item: The menu bar item to move.
    ///   - destination: The destination to move the menu bar item.
    ///   - timeout: The duration for each individual operation to wait
    ///     before throwing an error.
    func move(item: MenuBarItem, to destination: MoveDestination, timeout: Duration = .milliseconds(50)) async throws {
        guard item.isMovable else {
            throw EventError(code: .itemNotMovable, item: item)
        }
        guard let appState else {
            throw EventError(code: .cannotComplete, item: item)
        }

        guard try await !itemHasCorrectPosition(item: item, for: destination) else {
            logger.debug("\(item.logString, privacy: .public) already has correct position")
            return
        }

        do {
            // FIXME: Running these checks sequentially is prone to error.
            //
            // Say, for example, the user is holding down a modifier key while
            // dragging their mouse. It's reasonable that they could finish the
            // drag and start a new one, all while still holding the modifier.
            // Since the mouse movement and button checks would have finished at
            // the end of the first drag, we would completely miss this. We'd
            // have the same problem running the checks concurrently.
            //
            // We need a way to cooperatively restart each check as needed.
            try await waitForMouseToStopMoving()
            try await waitForAllMouseButtonsUp()
            try await waitForAllModifierKeysUp()
        } catch {
            throw EventError(code: .cannotComplete, item: item)
        }

        let source = try getEventSource(for: item)

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
            throw EventError(code: .cannotComplete, item: item)
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
        timeout: Duration = .milliseconds(250)
    ) async throws {
        guard let appState else {
            throw EventError(code: .cannotComplete, item: item)
        }

        let source = try getEventSource(for: item)
        let mouseLocation = try getMouseLocation(item: item)
        let itemBounds = try await getCurrentBounds(for: item)
        let pid = getEventPID(for: item)

        let mouseStates = mouseButton.mouseStates
        let clickPoint = itemBounds.center

        guard
            let clickEvent1 = CGEvent.menuBarItemEvent(
                source: source,
                type: .click(mouseStates.down),
                location: clickPoint,
                item: item,
                pid: pid
            ),
            let clickEvent2 = CGEvent.menuBarItemEvent(
                source: source,
                type: .click(mouseStates.up),
                location: clickPoint,
                item: item,
                pid: pid
            ),
            let fallbackEvent = CGEvent.menuBarItemEvent(
                source: source,
                type: .click(mouseStates.up),
                location: clickPoint,
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

        MouseHelpers.hideCursor()

        defer {
            MouseHelpers.warpCursor(to: mouseLocation)
            MouseHelpers.showCursor()
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
    private final class TempShownItemContext {
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

        init(tag: MenuBarItemTag, returnDestination: MoveDestination) {
            self.tag = tag
            self.returnDestination = returnDestination
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

        var maxX = if let frameOfNotch = screen.frameOfNotch {
            max(frameOfNotch.maxX + 20, applicationMenuFrame.maxX)
        } else {
            applicationMenuFrame.maxX
        }

        if let item = items.first, item.tag == .audioVideoModule {
            maxX += item.bounds.width
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
            try await move(item: item, to: .leftOfItem(targetItem))
        } catch {
            logger.error("Error showing item: \(error, privacy: .public)")
            return
        }

        let context = TempShownItemContext(tag: item.tag, returnDestination: destination)
        tempShownItemContexts.append(context)

        rehideTimer?.invalidate()
        defer {
            runRehideTimer()
        }

        await eventSleep(for: .milliseconds(50))

        let idsBeforeClick = Set(Bridging.getWindowList(option: .onScreen))

        do {
            try await click(item: item, with: mouseButton)
        } catch {
            logger.error("Error clicking item: \(error, privacy: .public)")
            return
        }

        await eventSleep(for: .milliseconds(500))

        let windowsAfterClick = WindowInfo.createWindows(option: .onScreen)

        context.shownInterfaceWindow = windowsAfterClick.first { window in
            window.ownerPID == item.sourcePID && !idsBeforeClick.contains(window.windowID)
        }
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

        while let context = tempShownItemContexts.popLast() {
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
            try await move(item: alwaysHidden, to: .leftOfItem(hidden))
        } catch {
            logger.error("Error enforcing control item order: \(error, privacy: .public)")
        }
    }
}

// MARK: - Helper Types

/// Mouse states for menu bar item move events.
private enum MenuBarItemMoveEventMouseState {
    case mouseDown
    case mouseUp

    var cgEventType: CGEventType {
        switch self {
        case .mouseDown: .leftMouseDown
        case .mouseUp: .leftMouseUp
        }
    }
}

/// Mouse states for menu bar item click events.
private enum MenuBarItemClickEventMouseState {
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
}

/// Event types for menu bar item events.
private enum MenuBarItemEventType {
    /// The event type for moving a menu bar item.
    case move(MenuBarItemMoveEventMouseState)
    /// The event type for clicking a menu bar item.
    case click(MenuBarItemClickEventMouseState)

    var cgEventType: CGEventType {
        switch self {
        case .move(let state): state.cgEventType
        case .click(let state): state.cgEventType
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
        case .click(let state): state.cgMouseButton
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

    /// The equivalent down and up mouse states for menu bar item click events.
    var mouseStates: (down: MenuBarItemClickEventMouseState, up: MenuBarItemClickEventMouseState) {
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

    /// Returns a Boolean value that indicates whether the given fields on
    /// this event are equivalent to the same fields on the given event.
    ///
    /// - Parameters:
    ///   - other: The event to compare with this event.
    ///   - fields: The fields to check.
    func matches(_ other: CGEvent, by fields: [CGEventField]) -> Bool {
        fields.allSatisfy { field in
            getIntegerValueField(field) == other.getIntegerValueField(field) &&
            getDoubleValueField(field) == other.getDoubleValueField(field)
        }
    }

    /// Posts the event to the given event tap location.
    ///
    /// - Parameter location: The event tap location to post the event to.
    func post(to location: EventTap.Location) {
        Logger.menuBarItemManager.debug(
            """
            Posting \(self.type.logString, privacy: .public) \
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

        if case .click = type {
            setIntegerValueField(.mouseEventWindowUnderMousePointer, value: windowID)
            setIntegerValueField(.mouseEventWindowUnderMousePointerThatCanHandleThisEvent, value: windowID)
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

private extension Logger {
    /// Logger for the menu bar item manager.
    static let menuBarItemManager = Logger(category: "MenuBarItemManager")
}
