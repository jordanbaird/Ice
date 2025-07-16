//
//  UniversalEventMonitor.swift
//  Ice
//

import Cocoa
import Combine

/// A type that monitors for local and global events.
final class UniversalEventMonitor {
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

extension UniversalEventMonitor {
    /// A publisher that emits local and global events for an event type mask.
    struct UniversalEventPublisher: Publisher {
        typealias Output = NSEvent
        typealias Failure = Never

        let mask: NSEvent.EventTypeMask

        func receive<S: Subscriber<Output, Failure>>(subscriber: S) {
            let subscription = UniversalEventSubscription(mask: mask, subscriber: subscriber)
            subscriber.receive(subscription: subscription)
        }
    }

    /// Returns a publisher that emits local and global events for the given
    /// event type mask.
    ///
    /// - Parameter mask: An event type mask specifying which events to publish.
    static func publisher(for mask: NSEvent.EventTypeMask) -> UniversalEventPublisher {
        UniversalEventPublisher(mask: mask)
    }
}

extension UniversalEventMonitor.UniversalEventPublisher {
    private final class UniversalEventSubscription<S: Subscriber<Output, Failure>>: Subscription {
        let mask: NSEvent.EventTypeMask
        private var subscriber: S?

        private lazy var monitor = UniversalEventMonitor(mask: mask) { [weak self] event in
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
