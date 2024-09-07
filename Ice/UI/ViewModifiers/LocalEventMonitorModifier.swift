//
//  LocalEventMonitorModifier.swift
//  Ice
//

import SwiftUI

@Observable
private class LocalEventMonitorModifierState {
    var monitor: LocalEventMonitor

    init(mask: NSEvent.EventTypeMask, action: @escaping (NSEvent) -> NSEvent?) {
        self.monitor = LocalEventMonitor(mask: mask, handler: action)
    }
}

private struct LocalEventMonitorView<Content: View>: View {
    @State private var state: LocalEventMonitorModifierState

    let content: Content

    init(mask: NSEvent.EventTypeMask, action: @escaping (NSEvent) -> NSEvent?, @ViewBuilder content: () -> Content) {
        self._state = State(wrappedValue: LocalEventMonitorModifierState(mask: mask, action: action))
        self.content = content()
    }

    var body: some View {
        content
            .onAppear {
                state.monitor.start()
            }
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
        LocalEventMonitorView(mask: mask, action: action) {
            self
        }
    }
}
