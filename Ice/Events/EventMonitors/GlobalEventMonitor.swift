//
//  GlobalEventMonitor.swift
//  Ice
//

import Cocoa
import Combine

/// A type that monitors for events outside the scope of the current process.
final class GlobalEventMonitor {
    private let mask: NSEvent.EventTypeMask
    private let handler: (NSEvent) -> Void
    private var monitor: Any?

    /// Creates an event monitor with the given event type mask and handler.
    ///
    /// - Parameters:
    ///   - mask: An event type mask specifying which events to monitor.
    ///   - handler: A handler to execute when the event monitor receives
    ///     an event corresponding to the event types in `mask`.
    init(mask: NSEvent.EventTypeMask, handler: @escaping (_ event: NSEvent) -> Void) {
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
        monitor = NSEvent.addGlobalMonitorForEvents(
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

extension GlobalEventMonitor {
    /// A publisher that emits global events for an event type mask.
    struct GlobalEventPublisher: Publisher {
        typealias Output = NSEvent
        typealias Failure = Never

        let mask: NSEvent.EventTypeMask

        func receive<S: Subscriber<Output, Failure>>(subscriber: S) {
            let subscription = GlobalEventSubscription(mask: mask, subscriber: subscriber)
            subscriber.receive(subscription: subscription)
        }
    }

    /// Returns a publisher that emits global events for the given event type mask.
    ///
    /// - Parameter mask: An event type mask specifying which events to publish.
    static func publisher(for mask: NSEvent.EventTypeMask) -> GlobalEventPublisher {
        GlobalEventPublisher(mask: mask)
    }
}

extension GlobalEventMonitor.GlobalEventPublisher {
    private final class GlobalEventSubscription<S: Subscriber<Output, Failure>>: Subscription {
        let mask: NSEvent.EventTypeMask
        private var subscriber: S?

        private lazy var monitor = GlobalEventMonitor(mask: mask) { [weak self] event in
            _ = self?.subscriber?.receive(event)
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
