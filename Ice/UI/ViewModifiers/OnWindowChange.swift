//
//  OnWindowChange.swift
//  Ice
//

import SwiftUI

private nonisolated struct WindowReaderView: NSViewRepresentable {
    final class Represented: NSView {
        let action: (NSWindow?) -> Void

        init(action: @escaping (NSWindow?) -> Void) {
            self.action = action
            super.init(frame: .zero)
        }

        @available(*, unavailable)
        required init?(coder: NSCoder) {
            fatalError("init(coder:) has not been implemented")
        }

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            Task {
                action(window)
            }
        }
    }

    let action: (NSWindow?) -> Void

    func makeNSView(context: Context) -> Represented {
        return Represented(action: action)
    }

    func updateNSView(_ nsView: Represented, context: Context) { }
}

extension View {
    /// Adds an action to perform when the view's window changes.
    ///
    /// - Parameter action: The action to perform when the view's window
    ///   changes. The closure passes the new window as a parameter. The
    ///   new window can be `nil`.
    nonisolated func onWindowChange(perform action: @escaping (_ window: NSWindow?) -> Void) -> some View {
        background {
            WindowReaderView(action: action)
        }
    }

    /// Updates the given binding when the view's window changes.
    ///
    /// - Parameter binding: The binding to update when the view's window
    ///   changes. The new window can be `nil`.
    nonisolated func onWindowChange(update binding: Binding<NSWindow?>) -> some View {
        onWindowChange { window in
            binding.wrappedValue = window
        }
    }
}
