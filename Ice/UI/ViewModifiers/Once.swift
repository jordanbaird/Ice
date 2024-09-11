//
//  Once.swift
//  Ice
//

import SwiftUI

private struct OnceModifier: ViewModifier {
    @State private var hasAppeared = false

    let onAppear: () -> Void

    func body(content: Content) -> some View {
        content.onAppear {
            if !hasAppeared {
                onAppear()
                hasAppeared = true
            }
        }
    }
}

extension View {
    /// Adds an action to perform exactly once, before the first
    /// time the view appears.
    ///
    /// - Parameter action: The action to perform.
    func once(perform action: @escaping () -> Void) -> some View {
        modifier(OnceModifier(onAppear: action))
    }
}
