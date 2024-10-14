//
//  SystemAppearance.swift
//  Ice
//

import SwiftUI

/// A value corresponding to a light or dark appearance.
enum SystemAppearance {
    /// A light appearance.
    case light
    /// A dark appearance.
    case dark

    /// The names of the light appearances used by the system.
    private static let systemLightAppearanceNames: Set<NSAppearance.Name> = [
        .aqua,
        .vibrantLight,
        .accessibilityHighContrastAqua,
        .accessibilityHighContrastVibrantLight,
    ]

    /// The names of the dark appearances used by the system.
    private static let systemDarkAppearanceNames: Set<NSAppearance.Name> = [
        .vibrantDark,
        .darkAqua,
        .accessibilityHighContrastDarkAqua,
        .accessibilityHighContrastVibrantDark,
    ]

    /// Returns the system appearance that exactly matches the given appearance,
    /// or `nil` if the system appearance cannot be determined.
    private static func exactMatch(for appearance: NSAppearance) -> SystemAppearance? {
        let name = appearance.name
        if systemDarkAppearanceNames.contains(name) {
            return .dark
        }
        if systemLightAppearanceNames.contains(name) {
            return .light
        }
        return nil
    }

    /// Returns the system appearance that best matches the given appearance,
    /// or `nil` if the system appearance cannot be determined.
    private static func bestMatch(for appearance: NSAppearance) -> SystemAppearance? {
        let lowercased = appearance.name.rawValue.lowercased()
        if lowercased.contains("dark") {
            return .dark
        }
        if lowercased.contains("light") || lowercased.contains("aqua") {
            return .light
        }
        return nil
    }

    /// Returns the system appearance of the given appearance.
    ///
    /// If a system appearance cannot be found that matches the given appearance,
    /// the ``light`` system appearance is returned.
    private static func systemAppearance(for appearance: NSAppearance) -> SystemAppearance {
        if let match = exactMatch(for: appearance) {
            return match
        }
        if let match = bestMatch(for: appearance) {
            return match
        }
        return .light
    }

    /// The current system appearance.
    static var current: SystemAppearance {
        systemAppearance(for: NSApp.effectiveAppearance)
    }

    /// The title key to display in the interface.
    var titleKey: LocalizedStringKey {
        switch self {
        case .light: "Light Appearance"
        case .dark: "Dark Appearance"
        }
    }
}
