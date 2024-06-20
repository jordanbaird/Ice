//
//  MenuBarItemManager.swift
//  Ice
//

import Bridging
import Cocoa
import Combine
import OSLog

/// A type that manages menu bar items.
@MainActor
class MenuBarItemManager: ObservableObject {
    @Published var cachedMenuBarItems = [MenuBarSection.Name: [MenuBarItem]]()

    private var tempShownItemsInfo = [(item: MenuBarItem, destination: MoveDestination)]()

    private var tempShownItemsTimer: Timer?

    private var dateOfLastTempShownItemsRehide: Date?

    private(set) weak var appState: AppState?

    private var cancellables = Set<AnyCancellable>()

    init(appState: AppState) {
        self.appState = appState
    }

    func performSetup() {
        configureCancellables()
        DispatchQueue.main.async {
            self.cacheCurrentMenuBarItems()
        }
    }

    private func configureCancellables() {
        var c = Set<AnyCancellable>()

        Timer.publish(every: 3, on: .main, in: .default)
            .autoconnect()
            .sink { [weak self] _ in
                self?.cacheCurrentMenuBarItems()
            }
            .store(in: &c)

        cancellables = c
    }
}

// MARK: - Cache Items

extension MenuBarItemManager {
    /// Caches the current menu bar items.
    private func cacheCurrentMenuBarItems() {
        guard tempShownItemsInfo.isEmpty else {
            Logger.itemManager.info("Items are temporarily shown, so deferring cache")
            return
        }

        if let dateOfLastTempShownItemsRehide {
            guard Date.now.timeIntervalSince(dateOfLastTempShownItemsRehide) > 1 else {
                Logger.itemManager.info("Items were recently rehidden, so deferring cache")
                return
            }
        }

        Logger.itemManager.info("Caching current menu bar items")

        let items = MenuBarItem.getMenuBarItemsPrivateAPI(onScreenOnly: false)

        guard
            let hiddenControlItem = items.first(where: { $0.info == .hiddenControlItem }),
            let alwaysHiddenControlItem = items.first(where: { $0.info == .alwaysHiddenControlItem })
        else {
            return
        }

        update(&cachedMenuBarItems) { cachedItems in
            cachedItems.removeAll()
            for item in items {
                // only items that can be hidden should be included
                guard item.canBeHidden else {
                    continue
                }

                // only items currently in the menu bar should be included
                guard item.isCurrentlyInMenuBar else {
                    continue
                }

                if item.owningApplication == .current {
                    // the Ice icon is the only item owned by Ice that should be included
                    guard item.title == ControlItem.Identifier.iceIcon.rawValue else {
                        continue
                    }
                }

                if item.frame.minX >= hiddenControlItem.frame.maxX {
                    cachedItems[.visible, default: []].append(item)
                } else if
                    item.frame.maxX <= hiddenControlItem.frame.minX,
                    item.frame.minX >= alwaysHiddenControlItem.frame.maxX
                {
                    cachedItems[.hidden, default: []].append(item)
                } else if item.frame.maxX <= alwaysHiddenControlItem.frame.minX {
                    cachedItems[.alwaysHidden, default: []].append(item)
                } else {
                    Logger.itemManager.warning("Item \"\(item.logString)\" not added to any section")
                }
            }
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
                "left of \"\(item.logString)\""
            case .rightOfItem(let item):
                "right of \"\(item.logString)\""
            }
        }
    }

    /// An error that can occur during menu bar item event processing.
    struct EventError: Error, CustomStringConvertible, LocalizedError {
        /// Error codes within the domain of menu bar item event errors.
        enum ErrorCode: Int {
            /// Indicates that an operation could not be completed.
            case couldNotComplete

            /// Indicates that the creation of a menu bar item event failed.
            case eventCreationFailure

            /// Indicates that the shared app state is invalid or could not be found.
            case invalidAppState

            /// Indicates that an event source could not be created or is otherwise
            /// invalid.
            case invalidEventSource

            /// Indicates that the location of the mouse cursor is invalid or could
            /// not be found.
            case invalidCursorLocation

            /// Indicates an invalid menu bar item.
            case invalidItem

            /// Indicates that the process is missing the required permissions.
            case missingPermissions

            /// Indicates that a menu bar item has no owning application.
            case noOwningApplication

            /// Indicates that a menu bar item cannot be moved.
            case notMovable

            /// Indicates that a menu bar item event operation timed out.
            case timeout
        }

        /// The error code of this error.
        let code: ErrorCode

        /// A simplified representation of the error's menu bar item.
        let info: MenuBarItemInfo?

        /// The message associated with this error.
        var message: String {
            switch code {
            case .couldNotComplete:
                "Could not complete"
            case .eventCreationFailure:
                "Failed to create event"
            case .invalidAppState:
                "Invalid app state"
            case .invalidEventSource:
                "Invalid event source"
            case .invalidCursorLocation:
                "Invalid cursor location"
            case .invalidItem:
                "Menu bar item is invalid"
            case .missingPermissions:
                "Missing permissions"
            case .noOwningApplication:
                "Menu bar item has no owning application"
            case .notMovable:
                "Menu bar item is not movable"
            case .timeout:
                "Operation timed out"
            }
        }

        var description: String {
            var parameters = [String]()
            parameters.append("message: \(message)")
            parameters.append("code: \(code.rawValue)")
            if let info {
                parameters.append("info: \(info)")
            }
            return "\(Self.self)(\(parameters.joined(separator: ", ")))"
        }

        var errorDescription: String? {
            message
        }

        init(code: ErrorCode, info: MenuBarItemInfo? = nil) {
            self.code = code
            self.info = info
        }

        init(code: ErrorCode, item: MenuBarItem?) {
            self.init(code: code, info: item?.info)
        }
    }

    /// Returns the current frame for the given item.
    ///
    /// - Parameter item: The item to return the current frame for.
    private func getCurrentFrame(for item: MenuBarItem) -> CGRect? {
        guard let frame = Bridging.getWindowFrame(for: item.window.windowID) else {
            Logger.move.error("Couldn't get current frame for \"\(item.logString)\"")
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
        case .application(let app):
            event.postToPid(app.processIdentifier)
        }
    }

    /// Posts the given event to an initial location, then forwards the event to a
    /// second location when an event tap at the initial location receives the event.
    ///
    /// - Parameters:
    ///   - event: The event to forward.
    ///   - initialLocation: The initial location to post the event.
    ///   - forwardedLocation: The location to forward the event.
    private func forwardEvent(
        _ event: CGEvent,
        from initialLocation: EventTap.Location,
        to forwardedLocation: EventTap.Location
    ) async throws {
        return try await withCheckedThrowingContinuation { continuation in
            let eventTap = EventTap(
                label: "MenuBarItem-Event-Forwarding",
                options: .defaultTap,
                location: initialLocation,
                place: .headInsertEventTap,
                types: [event.type]
            ) { [weak self] proxy, type, rEvent in
                guard let self else {
                    proxy.disable()
                    continuation.resume(throwing: EventError(code: .couldNotComplete))
                    return rEvent
                }

                // reenable the tap if disabled by the system
                if type == .tapDisabledByUserInput || type == .tapDisabledByTimeout {
                    proxy.enable()
                    return nil
                }

                // verify that the received event was the sent event
                guard eventsMatch([rEvent, event], by: CGEventField.menuBarItemEventFields) else {
                    return rEvent
                }

                Logger.move.info("Forwarding \(type.logString) from \(initialLocation.logString) to \(forwardedLocation.logString)")
                postEvent(event, to: forwardedLocation)

                proxy.disable()

                // small delay to prevent a timeout when running alongside certain
                // event tapping apps, such as Magnet
                Thread.sleep(forTimeInterval: 0.01)

                continuation.resume()

                return rEvent
            }

            eventTap.enable(timeout: .milliseconds(250)) {
                Logger.move.error("Event tap \"\(eventTap.label)\" timed out")
                eventTap.disable()
                continuation.resume()
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
        guard let currentFrame = getCurrentFrame(for: item) else {
            // this will be slow, but subsequent events will have a better chance of succeeding
            try await Task.sleep(for: .milliseconds(50))
            try await forwardEvent(event, from: initialLocation, to: forwardedLocation)
            try await Task.sleep(for: .milliseconds(50))
            return
        }
        try await forwardEvent(event, from: initialLocation, to: forwardedLocation)
        try await waitForFrameChange(of: item, initialFrame: currentFrame, timeout: .milliseconds(250))
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
                    Logger.move.info("Cancelling frame check")
                    throw FrameCheckCancellationError()
                }
                if currentFrame != initialFrame {
                    Logger.move.info("Menu bar item frame has changed to \(NSStringFromRect(currentFrame))")
                    return
                }
            }
        }

        do {
            try await frameCheckTask.value
        } catch is FrameCheckCancellationError {
            // this will be slow, but subsequent events will have a better chance of succeeding
            try await Task.sleep(for: .milliseconds(100))
        } catch is TaskTimeoutError {
            throw EventError(code: .timeout, item: item)
        }
    }

    /// Permits all events for an event source during the given suppression states,
    /// suppressing local events for the given interval.
    private func permitAllEvents(
        for stateID: CGEventSourceStateID,
        during states: [CGEventSuppressionState],
        suppressionInterval: TimeInterval
    ) throws {
        guard let source = CGEventSource(stateID: stateID) else {
            throw EventError(code: .invalidEventSource)
        }
        for state in states {
            source.setLocalEventsFilterDuringSuppressionState(.permitAllEvents, state: state)
        }
        source.localEventsSuppressionInterval = suppressionInterval
    }

    /// Moves a menu bar item to the given destination, without restoring
    /// the mouse pointer to its pre-move location.
    /// 
    /// - Parameters:
    ///   - item: A menu bar item to move.
    ///   - destination: A destination to move the menu bar item.
    ///   - source: An event source.
    private func moveItemWithoutRestoringMouseLocation(
        _ item: MenuBarItem,
        to destination: MoveDestination
    ) async throws {
        guard item.isMovable else {
            throw EventError(code: .notMovable, item: item)
        }
        guard let application = item.owningApplication else {
            throw EventError(code: .noOwningApplication, item: item)
        }
        guard let source = CGEventSource(stateID: .hidSystemState) else {
            throw EventError(code: .invalidEventSource, item: item)
        }

        try permitAllEvents(
            for: .combinedSessionState,
            during: [
                .eventSuppressionStateRemoteMouseDrag,
                .eventSuppressionStateSuppressionInterval,
            ],
            suppressionInterval: 0
        )

        let fallbackPoint = try getFallbackPoint(for: item)
        let startPoint = CGPoint(x: 20_000, y: 20_000)
        let endPoint = try getEndPoint(for: destination)
        let targetItem = getTargetItem(for: destination)

        guard
            let mouseDownEvent = CGEvent.menuBarItemEvent(
                with: .move(.mouseDown),
                location: startPoint,
                item: item,
                pid: item.ownerPID,
                source: source
            ),
            let mouseUpEvent = CGEvent.menuBarItemEvent(
                with: .move(.mouseUp),
                location: endPoint,
                item: targetItem,
                pid: item.ownerPID,
                source: source
            ),
            let fallbackEvent = CGEvent.menuBarItemEvent(
                with: .move(.mouseUp),
                location: fallbackPoint,
                item: item,
                pid: item.ownerPID,
                source: source
            )
        else {
            throw EventError(code: .eventCreationFailure, item: item)
        }

        do {
            try await forwardEvent(
                mouseDownEvent,
                from: .application(application),
                to: .sessionEventTap,
                waitingForFrameChangeOf: item
            )
            try await forwardEvent(
                mouseUpEvent,
                from: .application(application),
                to: .sessionEventTap,
                waitingForFrameChangeOf: item
            )
        } catch {
            postEvent(fallbackEvent, to: .sessionEventTap)
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
            Logger.move.info("\"\(item.logString)\" is already in the correct position")
            return
        }

        Logger.move.info("Moving \"\(item.logString)\" to \(destination.logString)")

        guard let appState else {
            throw EventError(code: .invalidAppState, item: item)
        }
        guard let cursorLocation = CGEvent(source: nil)?.location else {
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
            MouseCursor.warpPosition(to: cursorLocation)
            MouseCursor.show()
        }

        // item movement can occasionally fail; retry up to 5 total attempts,
        // throwing an error on the last attempt if it fails
        for n in 1...5 {
            do {
                try await moveItemWithoutRestoringMouseLocation(item, to: destination)
                if
                    let newFrame = getCurrentFrame(for: item),
                    newFrame != initialFrame
                {
                    Logger.move.info("Successfully moved \"\(item.logString)\"")
                    break
                } else {
                    throw EventError(code: .couldNotComplete, item: item)
                }
            } catch where n < 5 {
                Logger.move.error("Attempt \(n) to move \"\(item.logString)\" failed: \(error)")
                continue
            }
        }
    }

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
            throw EventError(code: .timeout, item: item)
        }
    }
}

// MARK: - Click Items

extension MenuBarItemManager {
    /// Clicks the given menu bar item with the left mouse button.
    func leftClick(item: MenuBarItem) async throws {
        guard let source = CGEventSource(stateID: .hidSystemState) else {
            throw EventError(code: .invalidEventSource, item: item)
        }
        guard let cursorLocation = CGEvent(source: nil)?.location else {
            throw EventError(code: .invalidCursorLocation, item: item)
        }
        guard let currentFrame = getCurrentFrame(for: item) else {
            throw EventError(code: .invalidItem, item: item)
        }

        MouseCursor.hide()

        defer {
            MouseCursor.warpPosition(to: cursorLocation)
            MouseCursor.show()
        }

        try permitAllEvents(
            for: .combinedSessionState,
            during: [
                .eventSuppressionStateRemoteMouseDrag,
                .eventSuppressionStateSuppressionInterval,
            ],
            suppressionInterval: 0
        )

        let clickPoint = CGPoint(x: currentFrame.midX, y: currentFrame.midY)

        guard
            let mouseDownEvent = CGEvent.menuBarItemEvent(
                with: .click(.mouseDown),
                location: clickPoint,
                item: item,
                pid: item.ownerPID,
                source: source
            ),
            let mouseUpEvent = CGEvent.menuBarItemEvent(
                with: .click(.mouseUp),
                location: clickPoint,
                item: item,
                pid: item.ownerPID,
                source: source
            )
        else {
            throw EventError(code: .eventCreationFailure, item: item)
        }

        Logger.itemManager.info("Left clicking \"\(item.logString)\"")

        postEvent(mouseDownEvent, to: .sessionEventTap)
        try await Task.sleep(for: .milliseconds(50))
        postEvent(mouseUpEvent, to: .sessionEventTap)
        try await Task.sleep(for: .milliseconds(50))
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

    /// Schedules a timer for the given interval, attempting to rehide the current
    /// temporarily shown items when the timer fires.
    private func runTempShownItemTimer(for interval: TimeInterval) {
        Logger.itemManager.info("Running rehide timer for temp shown items with interval: \(interval, format: .hybrid)")

        tempShownItemsTimer?.invalidate()
        tempShownItemsTimer = .scheduledTimer(withTimeInterval: interval, repeats: false) { [weak self] timer in
            guard let self else {
                timer.invalidate()
                return
            }

            Logger.itemManager.info("Rehide timer fired")

            Task {
                await self.rehideTempShownItems()
            }
        }
    }

    /// Temporarily shows the given item.
    ///
    /// This method moves the given item to the right of the control item for
    /// the "hidden" section. The item is cached alongside a destination that
    /// it will be automatically returned to. If `true` is passed to the
    /// `clickWhenFinished` parameter, the item is clicked once its movement
    /// is finished.
    ///
    /// - Parameters:
    ///   - item: An item to show.
    ///   - clickWhenFinished: A Boolean value that indicates whether the item
    ///     should be clicked once its movement has finished.
    func tempShowItem(_ item: MenuBarItem, clickWhenFinished: Bool) {
        Logger.itemManager.info("Temporarily showing \"\(item.logString)\"")

        let items = MenuBarItem.getMenuBarItemsPrivateAPI(onScreenOnly: false)

        guard let destination = getReturnDestination(for: item, in: items) else {
            Logger.itemManager.warning("No return destination for item \"\(item.logString)\"")
            return
        }
        guard let hiddenControlItem = items.first(where: { $0.info == .hiddenControlItem }) else {
            Logger.itemManager.warning("No hidden control item")
            return
        }

        tempShownItemsInfo.append((item, destination))

        Task {
            if clickWhenFinished {
                MouseCursor.hide()
                do {
                    try await slowMove(item: item, to: .rightOfItem(hiddenControlItem))
                    try await leftClick(item: item)
                } catch {
                    Logger.itemManager.error("ERROR: \(error)")
                }
                MouseCursor.show()
            } else {
                do {
                    try await move(item: item, to: .rightOfItem(hiddenControlItem))
                } catch {
                    Logger.itemManager.error("ERROR: \(error)")
                }
            }
            runTempShownItemTimer(for: 20)
        }
    }

    /// Rehides all temporarily shown items.
    ///
    /// If an item is currently showing its menu, this method waits for the menu
    /// to close before hiding the items.
    func rehideTempShownItems() async {
        guard !tempShownItemsInfo.isEmpty else {
            return
        }

        if let menuWindow = WindowInfo.getAllWindows().first(where: { $0.layer == 101 }) {
            Logger.itemManager.info("Waiting for menu to close before rehiding temp shown items")

            let menuCheckTask = Task.detached(timeout: .seconds(1)) {
                while Set(Bridging.getWindowList(option: .onScreen)).contains(menuWindow.windowID) {
                    try Task.checkCancellation()
                    try await Task.sleep(for: .milliseconds(10))
                }
            }
            do {
                try await menuCheckTask.value
            } catch is TaskTimeoutError {
                Logger.itemManager.info("Menu check task timed out. Switching to timer")
                runTempShownItemTimer(for: 3)
                return
            } catch {
                Logger.itemManager.error("ERROR: \(error)")
            }
        }

        Logger.itemManager.info("Rehiding temp shown items")

        while let (item, destination) = tempShownItemsInfo.popLast() {
            do {
                try await move(item: item, to: destination)
            } catch {
                Logger.itemManager.error("Failed to rehide \"\(item.logString)\": \(error)")
            }
        }

        tempShownItemsTimer?.invalidate()
        tempShownItemsTimer = nil

        dateOfLastTempShownItemsRehide = .now
    }

    /// Removes a temporarily shown item from the cache.
    ///
    /// This has the effect of ensuring that the item will not be returned to
    /// its previous location.
    func removeTempShownItemFromCache(with info: MenuBarItemInfo) {
        tempShownItemsInfo.removeAll(where: { $0.item.info == info })
    }
}

// MARK: - CGEvent Helpers

private extension CGEvent {
    enum MenuBarItemEventButtonState {
        case mouseDown
        case mouseUp
    }

    /// Event types that are used for moving menu bar items.
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
            case .mouseDown: .leftMouseDown
            case .mouseUp: .leftMouseUp
            }
        }

        var cgEventFlags: CGEventFlags {
            switch self {
            case .move(.mouseDown): .maskCommand
            case .move(.mouseUp), .click: []
            }
        }

        var mouseButton: CGMouseButton {
            switch buttonState {
            case .mouseDown, .mouseUp: .left
            }
        }
    }

    /// A context that manages the user data for menu bar item events.
    private enum MenuBarItemEventUserDataContext {
        /// The internal state of the context.
        private static var state: Int64 = 1000000

        /// Returns the current user data and increments the internal state.
        static func next() -> Int64 {
            defer { state += 1 }
            return state
        }
    }
}

// MARK: - CGEventField Helpers

private extension CGEventField {
    /// An undocumented field that enables moving off-screen menu bar items.
    static let specialField = CGEventField(rawValue: 0x33)! // swiftlint:disable:this force_unwrapping

    /// An array of integer event fields that can be used to compare two menu bar item events.
    static let menuBarItemEventFields: [CGEventField] = [
        .eventTargetUnixProcessID,
        .eventSourceUserData,
        .mouseEventWindowUnderMousePointer,
        .mouseEventWindowUnderMousePointerThatCanHandleThisEvent,
        .specialField,
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
    ///   - type: An instance of a type conforming to ``MenuBarItemEventType``.
    ///   - location: The location of the event. Does not need to be within the
    ///     bounds of the item.
    ///   - item: The target item of the event.
    ///   - pid: The target process identifier of the event. Does not need to be
    ///     the item's `ownerPID`.
    ///   - source: The source of the event.
    class func menuBarItemEvent(
        with type: MenuBarItemEventType,
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

        event.flags = type.cgEventFlags
        event.setSource(source)

        let targetPID = Int64(pid)
        let userData = MenuBarItemEventUserDataContext.next()
        let windowNumber = Int64(item.windowID)

        event.setIntegerValueField(.eventTargetUnixProcessID, value: targetPID)
        event.setIntegerValueField(.eventSourceUserData, value: userData)
        event.setIntegerValueField(.mouseEventWindowUnderMousePointer, value: windowNumber)
        event.setIntegerValueField(.mouseEventWindowUnderMousePointerThatCanHandleThisEvent, value: windowNumber)
        event.setIntegerValueField(.specialField, value: windowNumber)

        return event
    }
}

// MARK: - Logger

private extension Logger {
    static let itemManager = Logger(category: "MenuBarItemManager")
    static let move = Logger(category: "Move")
}
