//
//  BottomBar.swift
//  Ice
//

import SwiftUI

extension View {
    /// Adds the given view as a bottom bar to the current view.
    ///
    /// - Parameter content: A view to be added as a bottom bar to the current view.
    func bottomBar<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        safeAreaInset(edge: .bottom) {
            content()
                .background {
                    Rectangle()
                        .fill(.quinary.shadow(.inner(radius: 2)))
                        .shadow(radius: 2)
                }
        }
    }
}
