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
        local = LocalEventMonitor(mask: mask, handler: handler)
        global = GlobalEventMonitor(mask: mask, handler: { _ = handler($0) })
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
