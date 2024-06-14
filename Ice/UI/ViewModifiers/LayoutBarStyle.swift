//
//  LayoutBarStyle.swift
//  Ice
//

import SwiftUI

extension View {
    /// Returns a view that is drawn in the style of a layout bar.
    ///
    /// - Note: The view this modifier is applied to must be transparent, or the style will be
    ///   drawn incorrectly.
    ///
    /// - Parameters:
    ///   - menuBarManager: The menu bar manager that stores the average color of the menu bar.
    ///   - clipped: A Boolean value that indicates whether to clip the shape of the view to a
    ///     rounded rectangle.
    @MainActor
    @ViewBuilder
    func layoutBarStyle(menuBarManager: MenuBarManager, cornerRadius: CGFloat) -> some View {
        background {
            if let averageColor = menuBarManager.averageColor {
                Color(cgColor: averageColor).overlay(.menuBarTint)
            } else {
                Color.defaultLayoutBar
            }
        }
        .overlay {
            switch menuBarManager.appearanceManager.configuration.tintKind {
            case .none:
                EmptyView()
            case .solid:
                Color(cgColor: menuBarManager.appearanceManager.configuration.tintColor)
                    .opacity(0.2)
                    .allowsHitTesting(false)
            case .gradient:
                menuBarManager.appearanceManager.configuration.tintGradient
                    .opacity(0.2)
                    .allowsHitTesting(false)
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: cornerRadius))
    }
}
