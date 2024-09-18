//
//  LocalEventMonitorModifier.swift
//  Ice
//

import SwiftUI

private final class LocalEventMonitorModifierState: ObservableObject {
    let monitor: LocalEventMonitor

    init(mask: NSEvent.EventTypeMask, action: @escaping (NSEvent) -> NSEvent?) {
        self.monitor = LocalEventMonitor(mask: mask, handler: action)
        self.monitor.start()
    }

    deinit {
        monitor.stop()
    }
}

private struct LocalEventMonitorModifier: ViewModifier {
    @StateObject private var state: LocalEventMonitorModifierState

    init(mask: NSEvent.EventTypeMask, action: @escaping (NSEvent) -> NSEvent?) {
        let state = LocalEventMonitorModifierState(mask: mask, action: action)
        self._state = StateObject(wrappedValue: state)
    }

    func body(content: Content) -> some View {
        content
    }
}

extension View {
    /// Returns a view that performs the given action when events
    /// specified by the given mask are received.
    ///
    /// - Parameters:
    ///   - mask: An event type mask specifying which events to monitor.
    ///   - action: An action to perform when the event monitor receives
    ///     an event corresponding to the event types in `mask`.
    func localEventMonitor(
        mask: NSEvent.EventTypeMask,
        action: @escaping (NSEvent) -> NSEvent?
    ) -> some View {
        modifier(LocalEventMonitorModifier(mask: mask, action: action))
    }
}
