//
//  IceBarLocation.swift
//  Ice
//

import SwiftUI

/// Locations where the Ice Bar can appear.
enum IceBarLocation: Int, CaseIterable, Identifiable {
    /// The Ice Bar will appear in different locations based on context.
    case dynamic = 0

    /// The Ice Bar will appear centered below the mouse pointer.
    case mousePointer = 1

    /// The Ice Bar will appear centered below the Ice icon.
    case iceIcon = 2

    var id: Int { rawValue }

    /// Localized string key representation.
    var localized: LocalizedStringKey {
        switch self {
        case .dynamic: "Dynamic"
        case .mousePointer: "Mouse pointer"
        case .iceIcon: "Ice icon"
        }
    }
}
