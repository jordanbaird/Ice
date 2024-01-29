//
//  StateView.swift
//  Ice
//

import SwiftUI

/// A view that injects a binding to a state value into
/// a closure to produce a content view.
///
/// This view is useful for creating stateful previews.
///
/// ```swift
/// #Preview {
///     StateView(initialValue: 0) { state in
///         CustomStepper(value: state)
///     }
/// }
/// ```
struct StateView<Value, Content: View>: View {
    @State private var value: Value
    private let content: (Binding<Value>) -> Content

    /// Creates a view that wraps the given initial state
    /// value and injects a binding to the state into the
    /// given content producing closure.
    ///
    /// - Parameters:
    ///   - initialValue: The initial state value.
    ///   - content: A closure that produces a content view.
    init(
        initialValue: Value,
        @ViewBuilder content: @escaping (_ state: Binding<Value>) -> Content
    ) {
        self._value = State(wrappedValue: initialValue)
        self.content = content
    }

    var body: some View {
        content($value)
    }
}
