//
//  LocalEventMonitorView.swift
//  Ice
//

import SwiftUI

private struct LocalEventMonitorView: NSViewRepresentable {
    class Represented: NSView {
        let monitor: LocalEventMonitor

        init(mask: NSEvent.EventTypeMask, action: @escaping (NSEvent) -> NSEvent?) {
            let monitor = LocalEventMonitor(mask: mask, handler: action)
            monitor.start()
            self.monitor = monitor
            super.init(frame: .zero)
        }

        @available(*, unavailable)
        required init?(coder: NSCoder) {
            fatalError("init(coder:) has not been implemented")
        }

        deinit {
            monitor.stop()
        }
    }

    let mask: NSEvent.EventTypeMask
    let action: (NSEvent) -> NSEvent?

    func makeNSView(context: Context) -> Represented {
        Represented(mask: mask, action: action)
    }

    func updateNSView(_ nsView: Represented, context: Context) { }
}

extension View {
    /// Returns a view that performs the given action when
    /// events specified by the given mask are received.
    func localEventMonitor(
        mask: NSEvent.EventTypeMask,
        action: @escaping (NSEvent) -> NSEvent?
    ) -> some View {
        background {
            LocalEventMonitorView(mask: mask, action: action)
        }
    }
}
