//
//  Once.swift
//  Ice
//

import SwiftUI

private struct OnceAction {
    private var action: (() -> Void)?

    init(action: @escaping () -> Void) {
        self.action = action
    }

    mutating func callAsFunction() {
        if let action = action.take() {
            action()
        }
    }
}

private struct OnceModifier: ViewModifier {
    @State private var action: OnceAction

    init(action: @escaping () -> Void) {
        self.action = OnceAction(action: action)
    }

    func body(content: Content) -> some View {
        content.onAppear {
            action()
        }
    }
}

extension View {
    /// Adds an action to perform exactly once, before the first
    /// time the view appears.
    ///
    /// - Parameter action: The action to perform.
    func once(perform action: @escaping () -> Void) -> some View {
        modifier(OnceModifier(action: action))
    }
}

private struct OnceScene<Content: Scene>: Scene {
    @State private var action: OnceAction

    let content: Content

    init(content: Content, action: @escaping () -> Void) {
        self.action = OnceAction(action: action)
        self.content = content
    }

    var body: some Scene {
        content.onChange(of: 0, initial: true) {
            action()
        }
    }
}

extension Scene {
    /// Adds an action to perform exactly once, when the scene appears.
    ///
    /// - Parameter action: The action to perform.
    func once(perform action: @escaping () -> Void) -> some Scene {
        OnceScene(content: self, action: action)
    }
}
