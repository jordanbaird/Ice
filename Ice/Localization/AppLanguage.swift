//
//  AppLanguage.swift
//  Ice
//

import Foundation

/// The language to show in the interface.
enum AppLanguage: String, CaseIterable, Codable {
    case system
    case english
    case chinese

    /// The resolved language based on the current setting.
    var resolvedLanguage: Locale.LanguageCode {
        switch self {
        case .english:
            return .english
        case .chinese:
            return .chinese
        case .system:
            let preferred = Locale.preferredLanguages.first ?? "en"
            if preferred.hasPrefix("zh") {
                return .chinese
            }
            return .english
        }
    }
}

extension AppLanguage: Identifiable {
    var id: String { rawValue }

    var localizationKey: LocalizationKey {
        switch self {
        case .system: .systemLanguage
        case .english: .english
        case .chinese: .chinese
        }
    }
}
