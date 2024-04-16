//
//  UniversalEventMonitor.swift
//  Ice
//

import Cocoa

/// A type that monitors for events, regardless of scope.
class UniversalEventMonitor {
    private let local: LocalEventMonitor
    private let global: GlobalEventMonitor

    /// Creates an event monitor with the given event type mask and handler.
    ///
    /// - Parameters:
    ///   - mask: An event type mask specifying which events to monitor.
    ///   - handler: A handler to execute when the event monitor receives
    ///     an event corresponding to the event types in `mask`.
    init(mask: NSEvent.EventTypeMask, handler: @escaping (_ event: NSEvent) -> NSEvent?) {
        self.local = LocalEventMonitor(mask: mask, handler: handler)
        self.global = GlobalEventMonitor(mask: mask, handler: { _ = handler($0) })
    }

    deinit {
        stop()
    }

    /// Starts monitoring for events.
    func start() {
        local.start()
        global.start()
    }

    /// Stops monitoring for events.
    func stop() {
        local.stop()
        global.stop()
    }
}

@MainActor
extension UniversalEventMonitor {
    /// Returns a stream that yields events as they are received.
    ///
    /// Observe the events using `for-await-in` syntax.
    ///
    /// ```swift
    /// for await event in UniversalEventMonitor.events(for: .leftMouseDown) {
    ///     print("Left mouse down at \(event.location)")
    /// }
    /// ```
    ///
    /// - Parameter mask: A mask specifying the events to monitor.
    static func events(for mask: NSEvent.EventTypeMask) -> EventStream<NSEvent> {
        EventStream { continuation in
            let monitor = UniversalEventMonitor(mask: mask) { event in
                continuation.yield(SendableEvent(event: event))
                return event
            }
            continuation.onTermination = { _ in
                monitor.stop()
            }
            monitor.start()
        }
    }

    /// Returns a task that monitors events for the given mask.
    ///
    /// - Parameters:
    ///   - mask: A mask specifying the events to monitor.
    ///   - body: A closure to perform when events are received.
    ///   - onError: A closure to handle errors thrown from `body`.
    static func task(
        for mask: NSEvent.EventTypeMask,
        body: @escaping (SendableEvent<NSEvent>) async throws -> Void,
        onError: @escaping (any Error) async -> Void
    ) -> Task<Void, Never> {
        Task {
            for await event in events(for: mask) {
                do {
                    try await body(event)
                } catch {
                    await onError(error)
                }
            }
        }
    }

    /// Returns a task that monitors events for the given mask.
    ///
    /// - Parameters:
    ///   - mask: A mask specifying the events to monitor.
    ///   - body: A closure to perform when events are received.
    static func task(
        for mask: NSEvent.EventTypeMask,
        body: @escaping (SendableEvent<NSEvent>) async -> Void
    ) -> Task<Void, Never> {
        Task {
            for await event in events(for: mask) {
                await body(event)
            }
        }
    }
}
