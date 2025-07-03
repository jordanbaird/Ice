//
//  OnWindowChange.swift
//  Ice
//

import SwiftUI

private struct WindowReaderView: NSViewRepresentable {
    private final class Represented: NSView {
        var action: ((NSWindow?) -> Void)?

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            if let action {
                // Wrap the action in a Task to prevent SwiftUI update conflicts.
                Task {
                    action(window)
                }
            }
        }
    }

    var action: (NSWindow?) -> Void

    func makeNSView(context: Context) -> NSView {
        let view = Represented()
        view.action = action
        return view
    }

    func updateNSView(_: NSView, context: Context) { }
}

extension View {
    /// Adds an action to perform when the view's window changes.
    ///
    /// - Parameter action: The action to perform when the view's window
    ///   changes. The closure passes the new window as a parameter. The
    ///   new window can be `nil`.
    func onWindowChange(perform action: @escaping (_ window: NSWindow?) -> Void) -> some View {
        background {
            WindowReaderView(action: action)
        }
    }

    /// Updates the given binding when the view's window changes.
    ///
    /// - Parameter binding: The binding to update when the view's window
    ///   changes. The new window can be `nil`.
    func onWindowChange(update binding: Binding<NSWindow?>) -> some View {
        onWindowChange { window in
            binding.wrappedValue = window
        }
    }
}
