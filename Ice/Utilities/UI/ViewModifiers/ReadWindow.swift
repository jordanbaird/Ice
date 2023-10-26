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
        let onWindowChange: (NSWindow?) -> Void

        func makeNSView(context: Context) -> NSView {
            let view = NSView()
            context.coordinator.configure(for: view) { window in
                onWindowChange(window)
            }
            return view
        }

        func makeCoordinator() -> WindowObserver {
            WindowObserver()
        }

        func updateNSView(_: NSView, context: Context) { }
    }

    let onWindowChange: (NSWindow?) -> Void

    var body: some View {
        Representable(onWindowChange: onWindowChange)
    }
}

extension View {
    /// Reads the window of this view, performing the given closure when
    /// the window changes.
    ///
    /// - Parameter onChange: A closure to perform when the window changes.
    func readWindow(onChange: @escaping (NSWindow?) -> Void) -> some View {
        background {
            WindowReader(onWindowChange: onChange)
        }
    }

    /// Reads the window of this view, assigning it to the given binding.
    ///
    /// - Parameter window: A binding to use to store the view's window.
    func readWindow(window: Binding<NSWindow?>) -> some View {
        readWindow { window.wrappedValue = $0 }
    }
}
