//
//  MenuBarItemManager.swift
//  Ice
//

import Bridging
import Cocoa
import OSLog

/// A type that manages menu bar items.
@MainActor
class MenuBarItemManager {
    private(set) weak var appState: AppState?

    init(appState: AppState) {
        self.appState = appState
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

        var logString: String {
            switch self {
            case .leftOfItem(let item):
                "left of \"\(item.logString)\""
            case .rightOfItem(let item):
                "right of \"\(item.logString)\""
            }
        }
    }

    /// An error that can occur during menu bar item movement.
    struct MoveError: Error, CustomStringConvertible, LocalizedError {
        /// Error codes within the domain of menu bar item move errors.
        enum ErrorCode: Int {
            /// Indicates that an operation could not be completed.
            case couldNotComplete

            /// Indicates that the creation of a menu bar item movement event failed.
            case eventCreationFailure

            /// Indicates that the shared app state is invalid or could not be found.
            case invalidAppState

            /// Indicates that the location of the mouse cursor is invalid or could
            /// not be found.
            case invalidCursorLocation

            /// Indicates an invalid menu bar item.
            case invalidItem

            /// Indicates that the process is missing the required permissions.
            case missingPermissions

            /// Indicates that a menu bar item has no owning application, and cannot
            /// be moved.
            case noOwningApplication

            /// Indicates that a menu bar item cannot be moved.
            case notMovable

            /// Indicates that a menu bar item movement operation timed out.
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
                throw MoveError(code: .invalidItem, item: targetItem)
            }
            return CGPoint(x: currentFrame.minX, y: currentFrame.midY)
        case .rightOfItem(let targetItem):
            guard let currentFrame = getCurrentFrame(for: targetItem) else {
                throw MoveError(code: .invalidItem, item: targetItem)
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
            throw MoveError(code: .invalidItem, item: item)
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
            throw MoveError(code: .invalidItem, item: item)
        }
        switch destination {
        case .leftOfItem(let targetItem):
            guard let currentTargetFrame = getCurrentFrame(for: targetItem) else {
                throw MoveError(code: .invalidItem, item: targetItem)
            }
            return currentFrame.maxX == currentTargetFrame.minX
        case .rightOfItem(let targetItem):
            guard let currentTargetFrame = getCurrentFrame(for: targetItem) else {
                throw MoveError(code: .invalidItem, item: targetItem)
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
                label: "Event Forwarding",
                options: .defaultTap,
                location: initialLocation,
                place: .headInsertEventTap,
                types: [event.type]
            ) { [weak self] proxy, type, rEvent in
                guard let self else {
                    proxy.disable()
                    continuation.resume(throwing: MoveError(code: .couldNotComplete))
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

                Logger.move.info("Forwarding event from \(initialLocation.logString) to \(forwardedLocation.logString)")
                postEvent(event, to: forwardedLocation)

                proxy.disable()
                continuation.resume()

                return rEvent
            }

            eventTap.enable(timeout: .milliseconds(250)) {
                eventTap.disable()
                Logger.move.error("Event tap \"\(eventTap.label)\" timed out")
                Task {
                    defer { continuation.resume() }
                    try await Task.sleep(for: .milliseconds(100))
                }
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
        let frameCheckTask = Task.detached {
            while true {
                try Task.checkCancellation()
                guard let currentFrame = await self.getCurrentFrame(for: item) else {
                    Logger.move.info("Cancelling frame check")
                    // this will be slow, but subsequent events will have a better chance of succeeding
                    try await Task.sleep(for: .milliseconds(100))
                    return
                }
                if currentFrame != initialFrame {
                    Logger.move.info("Menu bar item frame has changed to \(NSStringFromRect(currentFrame))")
                    return
                }
            }
        }
        let timeoutTask = Task.detached {
            try await Task.sleep(for: timeout)
            frameCheckTask.cancel()
        }
        do {
            try await frameCheckTask.value
            timeoutTask.cancel()
        } catch is CancellationError {
            throw MoveError(code: .timeout, item: item)
        }
    }

    /// Suppresses local events for the given source.
    private func suppressLocalEvents(source: CGEventSource) {
        source.setLocalEventsFilterDuringSuppressionState(
            [.permitLocalMouseEvents, .permitLocalKeyboardEvents, .permitSystemDefinedEvents],
            state: .eventSuppressionStateRemoteMouseDrag
        )
        source.setLocalEventsFilterDuringSuppressionState(
            [.permitLocalMouseEvents, .permitLocalKeyboardEvents, .permitSystemDefinedEvents],
            state: .eventSuppressionStateSuppressionInterval
        )
        source.localEventsSuppressionInterval = 0
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
        to destination: MoveDestination,
        source: CGEventSource
    ) async throws {
        guard item.isMovable else {
            throw MoveError(code: .notMovable, item: item)
        }
        guard let application = item.owningApplication else {
            throw MoveError(code: .noOwningApplication, item: item)
        }

        suppressLocalEvents(source: source)

        let fallbackPoint = try getFallbackPoint(for: item)
        let startPoint = CGPoint(x: 20_000, y: 20_000)
        let endPoint = try getEndPoint(for: destination)
        let targetItem = getTargetItem(for: destination)

        guard
            let mouseDownEvent = CGEvent.menuBarItemEvent(
                with: .mouseDown,
                location: startPoint,
                item: item,
                pid: item.ownerPID,
                source: source
            ),
            let mouseUpEvent = CGEvent.menuBarItemEvent(
                with: .mouseUp,
                location: endPoint,
                item: targetItem,
                pid: item.ownerPID,
                source: source
            ),
            let fallbackEvent = CGEvent.menuBarItemEvent(
                with: .mouseUp,
                location: fallbackPoint,
                item: item,
                pid: item.ownerPID,
                source: source
            )
        else {
            throw MoveError(code: .eventCreationFailure, item: item)
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
    public func move(item: MenuBarItem, to destination: MoveDestination) async throws {
        if try itemHasCorrectPosition(item: item, for: destination) {
            Logger.move.info("\"\(item.logString)\" is already in the correct position")
            return
        }

        Logger.move.info("Moving \"\(item.logString)\" to \(destination.logString)")

        guard let appState else {
            throw MoveError(code: .invalidAppState, item: item)
        }
        guard let source = CGEventSource(stateID: .combinedSessionState) else {
            throw MoveError(code: .couldNotComplete, item: item)
        }
        guard let cursorLocation = CGEvent(source: nil)?.location else {
            throw MoveError(code: .invalidCursorLocation, item: item)
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

        try await moveItemWithoutRestoringMouseLocation(
            item,
            to: destination,
            source: source
        )
    }
}

// MARK: - CGEvent Helpers

private extension CGEvent {
    /// Event types that are used for moving menu bar items.
    enum MenuBarItemEventType {
        case mouseDown
        case mouseUp

        var cgEventType: CGEventType {
            switch self {
            case .mouseDown: .leftMouseDown
            case .mouseUp: .leftMouseUp
            }
        }

        var cgEventFlags: CGEventFlags {
            switch self {
            case .mouseDown: .maskCommand
            case .mouseUp: []
            }
        }

        var mouseButton: CGMouseButton {
            switch self {
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
    static let move = Logger(category: "Move")
}
