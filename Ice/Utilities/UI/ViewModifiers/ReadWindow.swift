//
//  ReadWindow.swift
//  Ice
//

import Combine
import SwiftUI

private struct WindowReader: View {
    private class WindowObserver: ObservableObject {
        private var cancellable: AnyCancellable?

        func configure(for view: NSView, onWindowChange: @escaping (NSWindow?) -> Void) {
            cancellable = view.publisher(for: \.window)
                .receive(on: DispatchQueue.main)
                .sink(receiveValue: onWindowChange)
        }
    }

    private struct Representable: NSViewRepresentable {
        @Binding var window: NSWindow?

        func makeNSView(context: Context) -> NSView {
            let view = NSView()
            context.coordinator.configure(for: view) { window in
                self.window = window
            }
            return view
        }

        func makeCoordinator() -> WindowObserver {
            WindowObserver()
        }

        func updateNSView(_: NSView, context: Context) { }
    }

    @Binding var window: NSWindow?

    var body: some View {
        Representable(window: $window)
    }
}

extension View {
    /// Reads the window of this view, assigning it to the given binding.
    ///
    /// - Parameter window: A binding to use to store the view's window.
    func readWindow(window: Binding<NSWindow?>) -> some View {
        background {
            WindowReader(window: window)
        }
    }
}
