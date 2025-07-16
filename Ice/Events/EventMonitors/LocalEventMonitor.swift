//
//  LocalEventMonitor.swift
//  Ice
//

import Cocoa
import Combine

/// A type that monitors for events within the scope of the current process.
final class LocalEventMonitor {
    private let mask: NSEvent.EventTypeMask
    private let handler: (NSEvent) -> NSEvent?
    private var monitor: Any?

    /// Creates an event monitor with the given event type mask and handler.
    ///
    /// - Parameters:
    ///   - mask: An event type mask specifying which events to monitor.
    ///   - handler: A handler to execute when the event monitor receives
    ///     an event corresponding to the event types in `mask`.
    init(mask: NSEvent.EventTypeMask, handler: @escaping (_ event: NSEvent) -> NSEvent?) {
        self.mask = mask
        self.handler = handler
    }

    deinit {
        stop()
    }

    /// Starts monitoring for events.
    func start() {
        guard monitor == nil else {
            return
        }
        monitor = NSEvent.addLocalMonitorForEvents(
            matching: mask,
            handler: handler
        )
    }

    /// Stops monitoring for events.
    func stop() {
        guard let monitor else {
            return
        }
        NSEvent.removeMonitor(monitor)
        self.monitor = nil
    }
}

extension LocalEventMonitor {
    /// A publisher that emits local events for an event type mask.
    struct LocalEventPublisher: Publisher {
        typealias Output = NSEvent
        typealias Failure = Never

        let mask: NSEvent.EventTypeMask

        func receive<S: Subscriber<Output, Failure>>(subscriber: S) {
            let subscription = LocalEventSubscription(mask: mask, subscriber: subscriber)
            subscriber.receive(subscription: subscription)
        }
    }

    /// Returns a publisher that emits local events for the given event type mask.
    ///
    /// - Parameter mask: An event type mask specifying which events to publish.
    static func publisher(for mask: NSEvent.EventTypeMask) -> LocalEventPublisher {
        LocalEventPublisher(mask: mask)
    }
}

extension LocalEventMonitor.LocalEventPublisher {
    private final class LocalEventSubscription<S: Subscriber<Output, Failure>>: Subscription {
        let mask: NSEvent.EventTypeMask
        private var subscriber: S?

        private lazy var monitor = LocalEventMonitor(mask: mask) { [weak self] event in
            _ = self?.subscriber?.receive(event)
            return event
        }

        init(mask: NSEvent.EventTypeMask, subscriber: S) {
            self.mask = mask
            self.subscriber = subscriber
            self.monitor.start()
        }

        func request(_ demand: Subscribers.Demand) { }

        func cancel() {
            monitor.stop()
            subscriber = nil
        }
    }
}
