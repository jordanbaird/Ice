//
//  WindowReader.swift
//  Ice
//

import Combine
import SwiftUI

struct WindowReader: View {
    private class Coordinator: ObservableObject {
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

        func makeCoordinator() -> Coordinator {
            Coordinator()
        }

        func updateNSView(_: NSView, context: Context) { }
    }

    @Binding var window: NSWindow?

    var body: some View {
        Representable(window: $window)
    }
}

extension View {
    func readWindow(window: Binding<NSWindow?>) -> some View {
        background(WindowReader(window: window))
    }
}
