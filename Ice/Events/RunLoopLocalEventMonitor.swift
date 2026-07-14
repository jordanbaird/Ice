//
//  RunLoopLocalEventMonitor.swift
//  Ice
//

import Cocoa
import Combine

final class RunLoopLocalEventMonitor {
    private let runLoop = CFRunLoopGetCurrent()
    private let mode: RunLoop.Mode
    private let handler: (NSEvent) -> NSEvent?
    private let observer: CFRunLoopObserver

    /// Creates an event monitor with the given event type mask and handler.
    ///
    /// - Parameters:
    ///   - mask: An event type mask specifying which events to monitor.
    ///   - handler: A handler to execute when the event monitor receives
    ///     an event corresponding to the event types in `mask`.
    init(
        mask: NSEvent.EventTypeMask,
        mode: RunLoop.Mode,
        handler: @escaping (_ event: NSEvent) -> NSEvent?
    ) {
        self.mode = mode
        self.handler = handler
        self.observer = CFRunLoopObserverCreateWithHandler(
            kCFAllocatorDefault,
            CFRunLoopActivity.beforeSources.rawValue,
            true,
            0
        ) { _, _ in
            var events = [NSEvent]()

            while let event = NSApp.nextEvent(matching: .any, until: nil, inMode: .default, dequeue: true) {
                events.append(event)
            }

            for event in events {
                var handledEvent: NSEvent?

                if !mask.contains(NSEvent.EventTypeMask(rawValue: 1 << event.type.rawValue)) {
                    handledEvent = event
                } else if let eventFromHandler = handler(event) {
                    handledEvent = eventFromHandler
                }

                guard let handledEvent else {
                    continue
                }

                NSApp.postEvent(handledEvent, atStart: false)
            }
        }
    }

    deinit {
        stop()
    }

    func start() {
        CFRunLoopAddObserver(
            runLoop,
            observer,
            CFRunLoopMode(mode.rawValue as CFString)
        )
    }

    func stop() {
        CFRunLoopRemoveObserver(
            runLoop,
            observer,
            CFRunLoopMode(mode.rawValue as CFString)
        )
    }
}

extension RunLoopLocalEventMonitor {
    /// A publisher that emits local events for an event type mask.
    struct RunLoopLocalEventPublisher: Publisher {
        typealias Output = NSEvent
        typealias Failure = Never

        let mask: NSEvent.EventTypeMask
        let mode: RunLoop.Mode

        func receive<S: Subscriber<Output, Failure>>(subscriber: S) {
            let subscription = RunLoopLocalEventSubscription(mask: mask, mode: mode, subscriber: subscriber)
            subscriber.receive(subscription: subscription)
        }
    }

    /// Returns a publisher that emits local events for the given event type mask.
    ///
    /// - Parameter mask: An event type mask specifying which events to publish.
    static func publisher(for mask: NSEvent.EventTypeMask, mode: RunLoop.Mode) -> RunLoopLocalEventPublisher {
        RunLoopLocalEventPublisher(mask: mask, mode: mode)
    }
}

extension RunLoopLocalEventMonitor.RunLoopLocalEventPublisher {
    private final class RunLoopLocalEventSubscription<S: Subscriber<Output, Failure>>: Subscription {
        let mask: NSEvent.EventTypeMask
        let mode: RunLoop.Mode
        private var subscriber: S?

        private lazy var monitor = RunLoopLocalEventMonitor(mask: mask, mode: mode) { [weak self] event in
            _ = self?.subscriber?.receive(event)
            return event
        }

        init(mask: NSEvent.EventTypeMask, mode: RunLoop.Mode, subscriber: S) {
            self.mask = mask
            self.mode = mode
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
