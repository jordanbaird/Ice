//
//  MenuBarAppearanceKind.swift
//  Ice
//

import SwiftUI

/// A type that specifies how the menu bar's color treatment is applied.
enum MenuBarAppearanceKind: Int, CaseIterable, Codable, Identifiable {
    /// No color treatment is applied.
    case none = 0
    /// Color is drawn as an overlay above status items, at a fixed 20% opacity.
    case tint = 1
    /// Color is drawn beneath status items, with user-controllable opacity.
    case backdrop = 2

    var id: Int { rawValue }

    var localized: LocalizedStringKey {
        switch self {
        case .none: "None"
        case .tint: "Tint"
        case .backdrop: "Backdrop"
        }
    }
}
