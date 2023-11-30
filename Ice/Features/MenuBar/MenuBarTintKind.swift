//
//  MenuBarTintKind.swift
//  Ice
//

import SwiftUI

/// A type that specifies how the menu bar is tinted.
enum MenuBarTintKind: Int, CaseIterable, Identifiable {
    /// The menu bar is not tinted.
    case none
    /// The menu bar is tinted with a solid color.
    case solid
    /// The menu bar is tinted with a gradient.
    case gradient

    var id: Int { rawValue }

    /// Localized string key representation.
    var localized: LocalizedStringKey {
        switch self {
        case .none: "None"
        case .solid: "Solid"
        case .gradient: "Gradient"
        }
    }
}
