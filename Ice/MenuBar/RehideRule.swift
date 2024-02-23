//
//  RehideRule.swift
//  Ice
//

import SwiftUI

/// A rule that determines how the auto-rehide feature works.
enum RehideRule: Int, CaseIterable, Identifiable {
    /// Menu bar items are rehidden when the focused app changes.
    case focusedApp = 0
    /// Menu bar items are rehidden after a given time interval.
    case timed = 1

    var id: Int { rawValue }

    /// Localized string key representation.
    var localized: LocalizedStringKey {
        switch self {
        case .focusedApp: "Focused app"
        case .timed: "Timed"
        }
    }
}
