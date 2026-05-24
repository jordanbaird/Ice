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
        LocalizedStringKey(localizationKey.rawValue)
    }

    /// The localization key for the location.
    var localizationKey: LocalizationKey {
        switch self {
        case .dynamic: .dynamic
        case .mousePointer: .mousePointer
        case .iceIcon: .iceIcon
        }
    }
}
