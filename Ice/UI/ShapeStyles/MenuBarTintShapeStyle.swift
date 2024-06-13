//
//  MenuBarTintShapeStyle.swift
//  Ice
//

import SwiftUI

/// A shape style that mimics the tint that the menu bar applies over
/// the desktop background.
struct MenuBarTintShapeStyle: ShapeStyle {
    func resolve(in environment: EnvironmentValues) -> some ShapeStyle {
        Material.bar
            .opacity(0.5)
            .blendMode(.softLight)
    }
}

extension ShapeStyle where Self == MenuBarTintShapeStyle {
    /// A shape style that mimics the tint that the menu bar applies over
    /// the desktop background.
    static var menuBarTint: MenuBarTintShapeStyle {
        MenuBarTintShapeStyle()
    }
}
