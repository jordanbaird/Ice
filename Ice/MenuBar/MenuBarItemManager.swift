//
//  MenuBarItemManager.swift
//  Ice
//

import Cocoa
import Combine
import OSLog

/// A type that manages menu bar items.
@MainActor
class MenuBarItemManager: ObservableObject {
    /// Cache for menu bar items.
    struct ItemCache: Hashable {
        var hiddenControlItem: MenuBarItem?
        var alwaysHiddenControlItem: MenuBarItem?

        private var items = [MenuBarSection.Name: [MenuBarItem]]()

        /// Appends the given item to the given section.
        mutating func appendItem(_ item: MenuBarItem, to section: MenuBarSection.Name) {
            items[section, default: []].append(item)
        }

        /// Clears the cached items for the given section.
        mutating func clearItems(for section: MenuBarSection.Name) {
            items[section, default: []].removeAll()
        }

        /// Clears the cache.
        mutating func clear() {
            hiddenControlItem = nil
            alwaysHiddenControlItem = nil
            items.removeAll()
        }

        /// Returns the items for the given section.
        func allItems(for section: MenuBarSection.Name) -> [MenuBarItem] {
            items[section, default: []]
        }

        /// Returns the items managed by Ice for the given section.
        func managedItems(for section: MenuBarSection.Name) -> [MenuBarItem] {
            allItems(for: section).filter { item in
                // Filter out items that can't be hidden.
                guard item.canBeHidden else {
                    return false
                }

                if item.owningApplication == .current {
                    // Ice icon is the only item owned by Ice that should be included.
                    guard item.title == ControlItem.Identifier.iceIcon.rawValue else {
                        return false
                    }
                }

                return true
            }
        }
    }

    /// Context for a temporarily shown menu bar item.
    private struct TempShownItemContext {
        let info: MenuBarItemInfo
        let returnDestination: MoveDestination
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

    @Published private(set) var itemCache = ItemCache()

    private(set) weak var appState: AppState?

    private var cancellables = Set<AnyCancellable>()

    private var cachedItemWindowIDs = [CGWindowID]()

    private var tempShownItemContexts = [TempShownItemContext]()
    private var tempShownItemsTimer: Timer?

    private(set) var lastItemMoveStartDate: Date?
    private var isMouseButtonDown = false
    private var mouseMovedCount = 0

    private let mouseTrackingMask: NSEvent.EventTypeMask = [
        .mouseMoved,
        .leftMouseDown,
        .rightMouseDown,
        .otherMouseDown,
        .leftMouseUp,
        .rightMouseUp,
        .otherMouseUp,
    ]

    init(appState: AppState) {
        self.appState = appState
    }

    func performSetup() {
        configureCancellables()
    }

    private func configureCancellables() {
        var c = Set<AnyCancellable>()

        Timer.publish(every: 5, on: .main, in: .default)
            .autoconnect()
            .merge(with: Just(.now))
            .sink { [weak self] _ in
                guard let self else {
                    return
                }
                Task {
                    await self.cacheItemsIfNeeded()
                }
            }
            .store(in: &c)

        Publishers.Merge(
            UniversalEventMonitor.publisher(for: mouseTrackingMask),
            RunLoopLocalEventMonitor.publisher(for: mouseTrackingMask, mode: .eventTracking)
        )
        .removeDuplicates()
        .sink { [weak self] event in
            guard let self else {
                return
            }
            switch event.type {
            case .mouseMoved:
                mouseMovedCount += 1
                DispatchQueue.main.asyncAfter(deadline: .now() + 1) {
                    self.mouseMovedCount = max(self.mouseMovedCount - 1, 0)
                }
            case .leftMouseDown, .rightMouseDown, .otherMouseDown:
                isMouseButtonDown = true
            case .leftMouseUp, .rightMouseUp, .otherMouseUp:
                isMouseButtonDown = false
            default:
                break
            }
        }
        .store(in: &c)

        cancellables = c
    }
}

// MARK: - Cache Items

extension MenuBarItemManager {
    /// Caches the given menu bar items, without checking whether the control items are in the correct order.
    private func uncheckedCacheItems(hiddenControlItem: MenuBarItem, alwaysHiddenControlItem: MenuBarItem?, otherItems: [MenuBarItem]) {
        func logNotAddedWarning(for item: MenuBarItem) {
            Logger.itemManager.warning("\(item.logString) doesn't seem to be in a section, so it wasn't cached")
        }

        Logger.itemManager.debug("Caching menu bar items")

        update(&itemCache) { cache in
            cache.clear()

            if let alwaysHiddenControlItem {
                for item in otherItems {
                    if item.frame.minX >= hiddenControlItem.frame.maxX {
                        cache.appendItem(item, to: .visible)
                    } else if
                        item.frame.maxX <= hiddenControlItem.frame.minX,
                        item.frame.minX >= alwaysHiddenControlItem.frame.maxX
                    {
                        cache.appendItem(item, to: .hidden)
                    } else if item.frame.maxX <= alwaysHiddenControlItem.frame.minX {
                        cache.appendItem(item, to: .alwaysHidden)
                    } else {
                        logNotAddedWarning(for: item)
                    }
                }
            } else {
                for item in otherItems {
                    if item.frame.minX >= hiddenControlItem.frame.maxX {
                        cache.appendItem(item, to: .visible)
                    } else if item.frame.maxX <= hiddenControlItem.frame.minX {
                        cache.appendItem(item, to: .hidden)
                    } else {
                        logNotAddedWarning(for: item)
                    }
                }
            }
        }
    }

    /// Caches the current menu bar items if needed, ensuring that the control items are in the correct order.
    private func cacheItemsIfNeeded() async {
        guard tempShownItemContexts.isEmpty else {
            Logger.itemManager.debug("Skipping item cache as items are temporarily shown")
            return
        }

        if let lastItemMoveStartDate {
            guard Date.now.timeIntervalSince(lastItemMoveStartDate) > 3 else {
                Logger.itemManager.debug("Skipping item cache as an item was recently moved")
                return
            }
        }

        let itemWindowIDs = Bridging.getWindowList(option: [.menuBarItems, .activeSpace])
        if cachedItemWindowIDs == itemWindowIDs {
            Logger.itemManager.debug("Skipping item cache as item windows have not changed")
            return
        } else {
            cachedItemWindowIDs = itemWindowIDs
        }

        var items = MenuBarItem.getMenuBarItemsPrivateAPI(onScreenOnly: false, activeSpaceOnly: true)

        let hiddenControlItem = items.firstIndex { $0.info == .hiddenControlItem }.map { items.remove(at: $0) }
        let alwaysHiddenControlItem = items.firstIndex { $0.info == .alwaysHiddenControlItem }.map { items.remove(at: $0) }

        guard let hiddenControlItem else {
            Logger.itemManager.warning("Missing control item for hidden section")
            Logger.itemManager.debug("Clearing item cache")
            itemCache.clear()
            return
        }

        do {
            if let alwaysHiddenControlItem {
                try await enforceControlItemOrder(hiddenControlItem: hiddenControlItem, alwaysHiddenControlItem: alwaysHiddenControlItem)
            }
            uncheckedCacheItems(hiddenControlItem: hiddenControlItem, alwaysHiddenControlItem: alwaysHiddenControlItem, otherItems: items)
        } catch {
            Logger.itemManager.error("Error enforcing control item order: \(error)")
            Logger.itemManager.debug("Clearing item cache")
            itemCache.clear()
        }
    }
}

// MARK: - Menu Bar Item Events -

extension MenuBarItemManager {
    /// An error that can occur during menu bar item event operations.
    struct EventError: Error, CustomStringConvertible, LocalizedError {
        /// Error codes within the domain of menu bar item event errors.
        enum ErrorCode: Int, CustomStringConvertible {
            /// Indicates that an operation could not be completed.
            case couldNotComplete

            /// Indicates that the creation of a menu bar item event failed.
            case eventCreationFailure

            /// Indicates that the shared app state is invalid or could not be found.
            case invalidAppState

            /// Indicates that an event source could not be created or is otherwise invalid.
            case invalidEventSource

            /// Indicates that the location of the mouse cursor is invalid or could not be found.
            case invalidCursorLocation

            /// Indicates an invalid menu bar item.
            case invalidItem

            /// Indicates that a menu bar item cannot be moved.
            case notMovable

            /// Indicates that a menu bar item event operation timed out.
            case eventOperationTimeout

            /// Indicates that a menu bar item frame check timed out.
            case frameCheckTimeout

            /// Indicates that an operation timed out.
            case otherTimeout

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
                case .frameCheckTimeout: "frameCheckTimeout"
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
            case .frameCheckTimeout:
                "Frame check timed out for \"\(item.displayName)\""
            case .otherTimeout:
                "Operation timed out for \"\(item.displayName)\""
            }
        }

        var description: String {
            var parameters = [String]()
            parameters.append("code: \(code.logString)")
            parameters.append("item: \(item.logString)")
            return "\(Self.self)(\(parameters.joined(separator: ", ")))"
        }

        var errorDescription: String? {
            message
        }

        var recoverySuggestion: String? {
            "Please try again. If the error persists, please file a bug report."
        }
    }
}

// MARK: - Move Items

extension MenuBarItemManager {
    /// A destination that a menu bar item can be moved to.
    enum MoveDestination {
        /// The menu bar item will be moved to the left of the given menu bar item.
        case leftOfItem(MenuBarItem)

        /// The menu bar item will be moved to the right of the given menu bar item.
        case rightOfItem(MenuBarItem)

        /// A string to use for logging purposes.
        var logString: String {
            switch self {
            case .leftOfItem(let item):
                "left of \(item.logString)"
            case .rightOfItem(let item):
                "right of \(item.logString)"
            }
        }
    }

    /// Returns the current frame for the given item.
    ///
    /// - Parameter item: The item to return the current frame for.
    private func getCurrentFrame(for item: MenuBarItem) -> CGRect? {
        guard let frame = Bridging.getWindowFrame(for: item.window.windowID) else {
            Logger.itemManager.error("Couldn't get current frame for \(item.logString)")
            return nil
        }
        return frame
    }

    /// Returns the end point for moving an item to the given destination.
    ///
    /// - Parameter destination: The destination to return the end point for.
    private func getEndPoint(for destination: MoveDestination) throws -> CGPoint {
        switch destination {
        case .leftOfItem(let targetItem):
            guard let currentFrame = getCurrentFrame(for: targetItem) else {
                throw EventError(code: .invalidItem, item: targetItem)
            }
            return CGPoint(x: currentFrame.minX, y: currentFrame.midY)
        case .rightOfItem(let targetItem):
            guard let currentFrame = getCurrentFrame(for: targetItem) else {
                throw EventError(code: .invalidItem, item: targetItem)
            }
            return CGPoint(x: currentFrame.maxX, y: currentFrame.midY)
        }
    }

    /// Returns the fallback point for returning the given item to its original
    /// position if a move fails.
    ///
    /// - Parameter item: The item to return the fallback point for.
    private func getFallbackPoint(for item: MenuBarItem) throws -> CGPoint {
        guard let currentFrame = getCurrentFrame(for: item) else {
            throw EventError(code: .invalidItem, item: item)
        }
        return CGPoint(x: currentFrame.midX, y: currentFrame.midY)
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
        guard let currentFrame = getCurrentFrame(for: item) else {
            throw EventError(code: .invalidItem, item: item)
        }
        switch destination {
        case .leftOfItem(let targetItem):
            guard let currentTargetFrame = getCurrentFrame(for: targetItem) else {
                throw EventError(code: .invalidItem, item: targetItem)
            }
            return currentFrame.maxX == currentTargetFrame.minX
        case .rightOfItem(let targetItem):
            guard let currentTargetFrame = getCurrentFrame(for: targetItem) else {
                throw EventError(code: .invalidItem, item: targetItem)
            }
            return currentFrame.minX == currentTargetFrame.maxX
        }
    }

    /// Returns a Boolean value that indicates whether the given events have the
    /// same values for each integer value field.
    ///
    /// - Parameters:
    ///   - events: The events to compare.
    ///   - integerFields: An array of integer value fields to compare on each event.
    private func eventsMatch(_ events: [CGEvent], by integerFields: [CGEventField]) -> Bool {
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
    private func postEvent(_ event: CGEvent, to location: EventTap.Location) {
        switch location {
        case .hidEventTap:
            event.post(tap: .cghidEventTap)
        case .sessionEventTap:
            event.post(tap: .cgSessionEventTap)
        case .annotatedSessionEventTap:
            event.post(tap: .cgAnnotatedSessionEventTap)
        case .pid(let pid):
            event.postToPid(pid)
        }
    }

    /// Delays an event tap callback from returning.
    private func delayEventTapCallback() {
        // Small delay to prevent timeouts when running alongside certain event tapping apps.
        // TODO: Try to find a better solution for this.
        Thread.sleep(forTimeInterval: 0.015)
    }

    /// Posts an event to the given event tap location and waits until it is
    /// received before returning.
    ///
    /// - Parameters:
    ///   - event: The event to post.
    ///   - location: The event tap location to post the event to.
    ///   - item: The menu bar item that the event affects.
    private func postEventAndWaitToReceive(_ event: CGEvent, to location: EventTap.Location, item: MenuBarItem) async throws {
        return try await withCheckedThrowingContinuation { continuation in
            let eventTap = EventTap(
                options: .defaultTap,
                location: location,
                place: .tailAppendEventTap,
                types: [event.type]
            ) { [weak self] proxy, type, rEvent in
                guard let self else {
                    proxy.disable()
                    continuation.resume(throwing: EventError(code: .couldNotComplete, item: item))
                    return rEvent
                }

                // Reenable the tap if disabled by the system.
                if type == .tapDisabledByUserInput || type == .tapDisabledByTimeout {
                    proxy.enable()
                    return nil
                }

                // Verify that the received event was the sent event.
                guard eventsMatch([rEvent, event], by: CGEventField.menuBarItemEventFields) else {
                    return rEvent
                }

                // Ensure the tap is enabled, preventing multiple calls to resume().
                guard proxy.isEnabled else {
                    Logger.itemManager.debug("Event tap \"\(proxy.label)\" is disabled (item: \(item.logString))")
                    return rEvent
                }

                Logger.itemManager.debug("Received \(type.logString) at \(location.logString) (item: \(item.logString))")

                proxy.disable()
                continuation.resume()

                return rEvent
            }

            eventTap.enable(timeout: .milliseconds(50)) {
                Logger.itemManager.error("Event tap \"\(eventTap.label)\" timed out (item: \(item.logString))")
                eventTap.disable()
                continuation.resume(throwing: EventError(code: .eventOperationTimeout, item: item))
            }

            postEvent(event, to: location)
        }
    }

    /// Posts the given event to an initial location, then forwards the event to a
    /// second location when an event tap at the initial location receives the event.
    ///
    /// - Parameters:
    ///   - event: The event to forward.
    ///   - initialLocation: The initial location to post the event.
    ///   - forwardedLocation: The location to forward the event.
    ///   - item: The menu bar item that the event affects.
    private func forwardEvent(
        _ event: CGEvent,
        from initialLocation: EventTap.Location,
        to forwardedLocation: EventTap.Location,
        item: MenuBarItem
    ) async throws {
        return try await withCheckedThrowingContinuation { continuation in
            let eventTap = EventTap(
                options: .defaultTap,
                location: initialLocation,
                place: .tailAppendEventTap,
                types: [event.type]
            ) { [weak self] proxy, type, rEvent in
                guard let self else {
                    proxy.disable()
                    continuation.resume(throwing: EventError(code: .couldNotComplete, item: item))
                    return rEvent
                }

                // Reenable the tap if disabled by the system.
                if type == .tapDisabledByUserInput || type == .tapDisabledByTimeout {
                    proxy.enable()
                    return nil
                }

                // Verify that the received event was the sent event.
                guard eventsMatch([rEvent, event], by: CGEventField.menuBarItemEventFields) else {
                    return rEvent
                }

                // Ensure the tap is enabled, preventing multiple calls to resume().
                guard proxy.isEnabled else {
                    Logger.itemManager.debug("Event tap \"\(proxy.label)\" is disabled (item: \(item.logString))")
                    return rEvent
                }

                Logger.itemManager.debug("Forwarding \(type.logString) from \(initialLocation.logString) to \(forwardedLocation.logString) (item: \(item.logString))")

                proxy.disable()
                continuation.resume()

                postEvent(event, to: forwardedLocation)
                delayEventTapCallback()

                return rEvent
            }

            eventTap.enable(timeout: .milliseconds(50)) {
                Logger.itemManager.error("Event tap \"\(eventTap.label)\" timed out (item: \(item.logString))")
                eventTap.disable()
                continuation.resume(throwing: EventError(code: .eventOperationTimeout, item: item))
            }

            postEvent(event, to: initialLocation)
        }
    }

    /// Posts the given event to an initial location, then forwards the event to a
    /// second location when an event tap at the initial location receives the event.
    /// After the event is forwarded, this function waits for the frame of the given
    /// menu bar item to change before returning.
    ///
    /// - Parameters:
    ///   - event: The event to forward.
    ///   - initialLocation: The initial location to post the event.
    ///   - forwardedLocation: The location to forward the event.
    ///   - item: The item whose frame should be observed.
    private func forwardEvent(
        _ event: CGEvent,
        from initialLocation: EventTap.Location,
        to forwardedLocation: EventTap.Location,
        waitingForFrameChangeOf item: MenuBarItem
    ) async throws {
        var error: EventError {
            EventError(code: .couldNotComplete, item: item)
        }
        guard let currentFrame = getCurrentFrame(for: item) else {
            try await forwardEvent(event, from: initialLocation, to: forwardedLocation, item: item)
            Logger.itemManager.warning("Couldn't get menu bar item frame for \(item.logString), so using fixed delay")
            // This will be slow, but subsequent events will have a better chance of succeeding.
            try await Task.sleep(for: .milliseconds(50))
            return
        }
        try await forwardEvent(event, from: initialLocation, to: forwardedLocation, item: item)
        try await waitForFrameChange(of: item, initialFrame: currentFrame, timeout: .milliseconds(50))
    }

    /// Waits for a menu bar item's frame to change from an initial frame.
    ///
    /// - Parameters:
    ///   - item: The item whose frame should be observed.
    ///   - initialFrame: An initial frame to compare the item's frame against.
    ///   - timeout: The amount of time to wait before throwing a timeout error.
    private func waitForFrameChange(of item: MenuBarItem, initialFrame: CGRect, timeout: Duration) async throws {
        struct FrameCheckCancellationError: Error { }

        let frameCheckTask = Task.detached(timeout: timeout) {
            while true {
                try Task.checkCancellation()
                guard let currentFrame = await self.getCurrentFrame(for: item) else {
                    throw FrameCheckCancellationError()
                }
                if currentFrame != initialFrame {
                    Logger.itemManager.debug("Menu bar item frame for \(item.logString) has changed to \(NSStringFromRect(currentFrame))")
                    return
                }
            }
        }

        do {
            try await frameCheckTask.value
        } catch is FrameCheckCancellationError {
            Logger.itemManager.warning("Menu bar item frame check for \(item.logString) was cancelled, so using fixed delay")
            // This will be slow, but subsequent events will have a better chance of succeeding.
            try await Task.sleep(for: .milliseconds(50))
        } catch is TaskTimeoutError {
            throw EventError(code: .frameCheckTimeout, item: item)
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
        Logger.itemManager.debug("Attempting to wake up \(item.logString)")

        guard let source = CGEventSource(stateID: .hidSystemState) else {
            throw EventError(code: .invalidEventSource, item: item)
        }
        guard let currentFrame = getCurrentFrame(for: item) else {
            throw EventError(code: .invalidItem, item: item)
        }
        guard let mouseUpEvent = CGEvent.menuBarItemEvent(
            type: .move(.leftMouseUp),
            location: CGPoint(x: currentFrame.midX, y: currentFrame.midY),
            item: item,
            pid: item.ownerPID,
            source: source
        ) else {
            throw EventError(code: .eventCreationFailure, item: item)
        }

        try await forwardEvent(mouseUpEvent, from: .pid(item.ownerPID), to: .sessionEventTap, item: item)
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
            try await forwardEvent(mouseDownEvent, from: .pid(item.ownerPID), to: .sessionEventTap, waitingForFrameChangeOf: item)
            try await forwardEvent(mouseUpEvent, from: .pid(item.ownerPID), to: .sessionEventTap, waitingForFrameChangeOf: item)
        } catch {
            do {
                Logger.itemManager.debug("Posting fallback event for moving \(item.logString)")
                // Catch this, as we still want to throw the existing error if the fallback fails.
                try await postEventAndWaitToReceive(fallbackEvent, to: .sessionEventTap, item: item)
            } catch {
                Logger.itemManager.error("Failed to post fallback event for moving \(item.logString)")
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
            Logger.itemManager.debug("\(item.logString) is already in the correct position")
            return
        }

        Logger.itemManager.info("Moving \(item.logString) to \(destination.logString)")

        guard let appState else {
            throw EventError(code: .invalidAppState, item: item)
        }
        guard let cursorLocation = MouseCursor.location(flipped: true) else {
            throw EventError(code: .invalidCursorLocation, item: item)
        }
        guard let initialFrame = getCurrentFrame(for: item) else {
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
                guard let newFrame = getCurrentFrame(for: item) else {
                    throw EventError(code: .invalidItem, item: item)
                }
                if newFrame != initialFrame {
                    Logger.itemManager.info("Successfully moved \(item.logString)")
                    break
                } else {
                    throw EventError(code: .couldNotComplete, item: item)
                }
            } catch where n < 5 {
                Logger.itemManager.warning("Attempt \(n) to move \(item.logString) failed (error: \(error))")
                try await wakeUpItem(item)
                Logger.itemManager.info("Retrying move of \(item.logString)")
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
    func slowMove(item: MenuBarItem, to destination: MoveDestination) async throws {
        try await move(item: item, to: destination)
        let waitTask = Task.detached(timeout: .seconds(1)) {
            while true {
                try Task.checkCancellation()
                if try await self.itemHasCorrectPosition(item: item, for: destination) {
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
    /// Clicks the given menu bar item with the given button states.
    private func click(
        item: MenuBarItem,
        mouseDownButtonState: CGEvent.MenuBarItemEventButtonState,
        mouseUpButtonState: CGEvent.MenuBarItemEventButtonState
    ) async throws {
        guard let source = CGEventSource(stateID: .hidSystemState) else {
            throw EventError(code: .invalidEventSource, item: item)
        }
        guard let cursorLocation = MouseCursor.location(flipped: true) else {
            throw EventError(code: .invalidCursorLocation, item: item)
        }
        guard let currentFrame = getCurrentFrame(for: item) else {
            throw EventError(code: .invalidItem, item: item)
        }

        let clickPoint = CGPoint(x: currentFrame.midX, y: currentFrame.midY)

        guard
            let mouseDownEvent = CGEvent.menuBarItemEvent(
                type: .click(mouseDownButtonState),
                location: clickPoint,
                item: item,
                pid: item.ownerPID,
                source: source
            ),
            let mouseUpEvent = CGEvent.menuBarItemEvent(
                type: .click(mouseUpButtonState),
                location: clickPoint,
                item: item,
                pid: item.ownerPID,
                source: source
            ),
            let fallbackEvent = CGEvent.menuBarItemEvent(
                type: .click(mouseUpButtonState),
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
            try await postEventAndWaitToReceive(mouseDownEvent, to: .sessionEventTap, item: item)
            try await postEventAndWaitToReceive(mouseUpEvent, to: .sessionEventTap, item: item)
        } catch {
            do {
                Logger.itemManager.debug("Posting fallback event for clicking \(item.logString)")
                // Catch this, as we still want to throw the existing error if the fallback fails.
                try await postEventAndWaitToReceive(fallbackEvent, to: .sessionEventTap, item: item)
            } catch {
                Logger.itemManager.error("Failed to post fallback event for clicking \(item.logString)")
            }
            throw error
        }
    }

    /// Clicks the given menu bar item with the left mouse button.
    func leftClick(item: MenuBarItem) async throws {
        Logger.itemManager.info("Left clicking \(item.logString)")
        try await click(item: item, mouseDownButtonState: .leftMouseDown, mouseUpButtonState: .leftMouseUp)
    }

    /// Clicks the given menu bar item with the right mouse button.
    func rightClick(item: MenuBarItem) async throws {
        Logger.itemManager.info("Right clicking \(item.logString)")
        try await click(item: item, mouseDownButtonState: .rightMouseDown, mouseUpButtonState: .rightMouseUp)
    }

    /// Clicks the given menu bar item with the center mouse button.
    func centerClick(item: MenuBarItem) async throws {
        Logger.itemManager.info("Center clicking \(item.logString)")
        try await click(item: item, mouseDownButtonState: .otherMouseDown, mouseUpButtonState: .otherMouseUp)
    }
}

// MARK: - Temporarily Show Items

extension MenuBarItemManager {
    /// Gets the destination to return the given item to after it is temporarily shown.
    private func getReturnDestination(for item: MenuBarItem, in items: [MenuBarItem]) -> MoveDestination? {
        let info = item.info
        if let index = items.firstIndex(where: { $0.info == info }) {
            if items.indices.contains(index + 1) {
                return .leftOfItem(items[index + 1])
            } else if items.indices.contains(index - 1) {
                return .rightOfItem(items[index - 1])
            }
        }
        return nil
    }

    /// Schedules a timer for the given interval, attempting to rehide the current temporarily shown
    /// items when the timer fires.
    private func runTempShownItemTimer(for interval: TimeInterval) {
        Logger.itemManager.debug("Running rehide timer for temporarily shown items with interval: \(interval, format: .hybrid)")
        tempShownItemsTimer?.invalidate()
        tempShownItemsTimer = .scheduledTimer(withTimeInterval: interval, repeats: false) { [weak self] timer in
            guard let self else {
                timer.invalidate()
                return
            }
            Logger.itemManager.debug("Rehide timer fired")
            Task {
                await self.rehideTempShownItems()
            }
        }
    }

    /// Temporarily shows the given item.
    ///
    /// The item is cached alongside a destination that it will be automatically returned to. If `true`
    /// is passed to the `clickWhenFinished` parameter, the item is clicked once movement is finished.
    ///
    /// - Parameters:
    ///   - item: An item to show.
    ///   - clickWhenFinished: A Boolean value that indicates whether the item should be clicked once
    ///     movement has finished.
    ///   - mouseButton: The mouse button of the click.
    func tempShowItem(_ item: MenuBarItem, clickWhenFinished: Bool, mouseButton: CGMouseButton) {
        let rehideInterval: TimeInterval = 20

        guard
            let appState,
            let screen = NSScreen.main,
            let applicationMenuFrame = appState.menuBarManager.getApplicationMenuFrame(for: screen.displayID)
        else {
            Logger.itemManager.warning("No application menu frame, so not showing \(item.logString)")
            return
        }

        Logger.itemManager.info("Temporarily showing \(item.logString)")

        var items = MenuBarItem.getMenuBarItemsPrivateAPI(onScreenOnly: false, activeSpaceOnly: true)

        guard let destination = getReturnDestination(for: item, in: items) else {
            Logger.itemManager.warning("No return destination for \(item.logString)")
            return
        }

        // Remove all items up to the hidden control item.
        items.trimPrefix { $0.info != .hiddenControlItem }
        // Remove the hidden control item.
        items.removeFirst()
        // Remove all offscreen items.
        items.trimPrefix { !$0.isOnScreen }

        if let rightArea = screen.auxiliaryTopRightArea {
            // Remove items to the right of the notch until we have enough room to show this item.
            items.trimPrefix { $0.frame.minX - item.frame.width <= rightArea.minX + 20 }
        } else {
            // Remove items to the right of the application menu frame until we have enough room
            // to show this item.
            items.trimPrefix { $0.frame.minX - item.frame.width <= applicationMenuFrame.maxX }
        }

        guard let targetItem = items.first else {
            Logger.itemManager.warning("Not enough room to show \(item.logString)")
            return
        }

        let initialWindows = WindowInfo.getOnScreenWindows()

        Task {
            if clickWhenFinished {
                do {
                    try await slowMove(item: item, to: .leftOfItem(targetItem))
                    switch mouseButton {
                    case .left:
                        try await leftClick(item: item)
                    case .right:
                        try await rightClick(item: item)
                    case .center:
                        try await centerClick(item: item)
                    @unknown default:
                        assertionFailure("Unknown mouse button \(mouseButton)")
                    }
                } catch {
                    Logger.itemManager.error("ERROR: \(error)")
                }
            } else {
                do {
                    try await move(item: item, to: .leftOfItem(targetItem))
                } catch {
                    Logger.itemManager.error("ERROR: \(error)")
                }
            }

            try? await Task.sleep(for: .milliseconds(100))

            let currentWindows = WindowInfo.getOnScreenWindows()

            let shownInterfaceWindow = currentWindows.first { currentWindow in
                currentWindow.ownerPID == item.ownerPID &&
                !initialWindows.contains { initialWindow in
                    currentWindow.windowID == initialWindow.windowID
                }
            }

            let context = TempShownItemContext(info: item.info, returnDestination: destination, shownInterfaceWindow: shownInterfaceWindow)
            tempShownItemContexts.append(context)

            runTempShownItemTimer(for: rehideInterval)
        }
    }

    /// Rehides all temporarily shown items.
    ///
    /// If an item is currently showing its menu, this method waits for the menu to close before
    /// hiding the items.
    func rehideTempShownItems() async {
        guard !tempShownItemContexts.isEmpty else {
            return
        }

        let interfaceCheckTask = Task.detached(timeout: .seconds(1)) {
            while await self.tempShownItemContexts.contains(where: { $0.isShowingInterface }) {
                try Task.checkCancellation()
                try await Task.sleep(for: .milliseconds(10))
            }
        }
        do {
            try await interfaceCheckTask.value
        } catch is TaskTimeoutError {
            Logger.itemManager.debug("Menu check task timed out, switching to timer")
            runTempShownItemTimer(for: 3)
            return
        } catch {
            Logger.itemManager.error("ERROR: \(error)")
        }

        Logger.itemManager.info("Rehiding temporarily shown items")

        var failedContexts = [TempShownItemContext]()

        let items = MenuBarItem.getMenuBarItemsPrivateAPI(onScreenOnly: false, activeSpaceOnly: true)

        while let context = tempShownItemContexts.popLast() {
            guard let item = items.first(where: { $0.info == context.info }) else {
                continue
            }
            do {
                try await move(item: item, to: context.returnDestination)
            } catch {
                Logger.itemManager.error("Failed to rehide \(item.logString) (error: \(error))")
                failedContexts.append(context)
            }
        }

        if failedContexts.isEmpty {
            tempShownItemsTimer?.invalidate()
            tempShownItemsTimer = nil
        } else {
            tempShownItemContexts = failedContexts
            runTempShownItemTimer(for: 3)
        }
    }

    /// Removes a temporarily shown item from the cache.
    ///
    /// This has the effect of ensuring that the item will not be returned to its previous location.
    func removeTempShownItemFromCache(with info: MenuBarItemInfo) {
        tempShownItemContexts.removeAll { $0.info == info }
    }
}

// MARK: - Arrange Items

extension MenuBarItemManager {
    /// Enforces the order of the given control items, ensuring that the always-hidden control item stays
    /// to the left of the hidden control item.
    ///
    /// - Parameters:
    ///   - hiddenControlItem: A menu bar item that represents the control item for the hidden section.
    ///   - alwaysHiddenControlItem: A menu bar item that represents the control item for the always-hidden section.
    func enforceControlItemOrder(hiddenControlItem: MenuBarItem, alwaysHiddenControlItem: MenuBarItem) async throws {
        guard !isMouseButtonDown else {
            Logger.itemManager.debug("Mouse button is down, so will not enforce control item order")
            return
        }
        guard mouseMovedCount <= 0 else {
            Logger.itemManager.debug("Mouse has recently moved, so will not enforce control item order")
            return
        }
        if hiddenControlItem.frame.maxX <= alwaysHiddenControlItem.frame.minX {
            Logger.itemManager.info("Arranging menu bar items")
            try await slowMove(item: alwaysHiddenControlItem, to: .leftOfItem(hiddenControlItem))
        }
    }
}

// MARK: - CGEvent Helpers

private extension CGEvent {
    /// Button states for menu bar item events.
    enum MenuBarItemEventButtonState {
        case leftMouseDown
        case leftMouseUp
        case rightMouseDown
        case rightMouseUp
        case otherMouseDown
        case otherMouseUp
    }

    /// Event types for menu bar item events.
    enum MenuBarItemEventType {
        case move(MenuBarItemEventButtonState)
        case click(MenuBarItemEventButtonState)

        var buttonState: MenuBarItemEventButtonState {
            switch self {
            case .move(let state), .click(let state): state
            }
        }

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

        var cgEventFlags: CGEventFlags {
            switch self {
            case .move(.leftMouseDown): .maskCommand
            case .move, .click: []
            }
        }

        var mouseButton: CGMouseButton {
            switch buttonState {
            case .leftMouseDown, .leftMouseUp: .left
            case .rightMouseDown, .rightMouseUp: .right
            case .otherMouseDown, .otherMouseUp: .center
            }
        }
    }

    /// A context that manages the user data for menu bar item events.
    enum MenuBarItemEventUserDataContext {
        /// The internal state of the context.
        private static var state: Int64 = 0x1CE

        /// Returns the current user data and increments the internal state.
        static func next() -> Int64 {
            defer { state += 1 }
            return state
        }
    }
}

// MARK: - CGEventField Helpers

private extension CGEventField {
    /// Key to access a field that contains the window number of the event.
    static let windowNumber = CGEventField(rawValue: 0x33)! // swiftlint:disable:this force_unwrapping

    /// An array of integer event fields that can be used to compare two menu bar item events.
    static let menuBarItemEventFields: [CGEventField] = [
        .eventSourceUserData,
        .mouseEventWindowUnderMousePointer,
        .mouseEventWindowUnderMousePointerThatCanHandleThisEvent,
        .windowNumber,
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

// MARK: - CGEvent Constructor

private extension CGEvent {
    /// Returns an event that can be sent to the given menu bar item.
    ///
    /// - Parameters:
    ///   - type: The type of the event.
    ///   - location: The location of the event. Does not need to be within the bounds of the item.
    ///   - item: The target item of the event.
    ///   - pid: The target process identifier of the event. Does not need to be the item's `ownerPID`.
    ///   - source: The source of the event.
    class func menuBarItemEvent(type: MenuBarItemEventType, location: CGPoint, item: MenuBarItem, pid: pid_t, source: CGEventSource) -> CGEvent? {
        let mouseType = type.cgEventType
        let mouseButton = type.mouseButton

        guard let event = CGEvent(mouseEventSource: source, mouseType: mouseType, mouseCursorPosition: location, mouseButton: mouseButton) else {
            return nil
        }

        event.flags = type.cgEventFlags

        let targetPID = Int64(pid)
        let userData = MenuBarItemEventUserDataContext.next()
        let windowNumber = Int64(item.windowID)

        event.setIntegerValueField(.eventTargetUnixProcessID, value: targetPID)
        event.setIntegerValueField(.eventSourceUserData, value: userData)
        event.setIntegerValueField(.mouseEventWindowUnderMousePointer, value: windowNumber)
        event.setIntegerValueField(.mouseEventWindowUnderMousePointerThatCanHandleThisEvent, value: windowNumber)
        event.setIntegerValueField(.windowNumber, value: windowNumber)

        if case .click = type {
            event.setIntegerValueField(.mouseEventClickState, value: 1)
        }

        return event
    }
}

private extension Logger {
    static let itemManager = Logger(category: "MenuBarItemManager")
}
