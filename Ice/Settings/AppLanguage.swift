//
//  AppLanguage.swift
//  Ice
//

import AppKit
import Foundation

/// The user-selectable language for the app.
enum AppLanguage: String, CaseIterable, Identifiable {
    /// Follow the system language.
    case system
    /// Simplified Chinese.
    case simplifiedChinese = "zh-Hans"
    /// English.
    case english = "en"

    var id: String { rawValue }

    /// The name displayed for the language in the picker.
    ///
    /// Native language names are intentionally not localized.
    var displayName: String {
        switch self {
        case .system: String(localized: "Follow System")
        case .simplifiedChinese: "简体中文"
        case .english: "English"
        }
    }

    /// The language currently selected by the user, as stored in the app's
    /// `AppleLanguages` preference. Returns `.system` if no override exists.
    static var current: AppLanguage {
        guard
            let bundleID = Bundle.main.bundleIdentifier,
            let domain = UserDefaults.standard.persistentDomain(forName: bundleID),
            let languages = domain["AppleLanguages"] as? [String],
            let first = languages.first,
            let language = AppLanguage(rawValue: first)
        else {
            return .system
        }
        return language
    }

    /// Writes the selection to the app's `AppleLanguages` preference.
    /// A value of `.system` removes the override, restoring the default
    /// behavior of following the system language.
    func apply() {
        switch self {
        case .system:
            UserDefaults.standard.removeObject(forKey: "AppleLanguages")
        default:
            UserDefaults.standard.set([rawValue], forKey: "AppleLanguages")
        }
        UserDefaults.standard.synchronize()
    }

    /// Relaunches the app so the new language takes effect.
    static func relaunch() {
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/bin/sh")
        task.arguments = ["-c", "sleep 1; open \"\(Bundle.main.bundlePath)\""]
        do {
            try task.run()
        } catch {
            Logger.appLanguage.error("Failed to relaunch: \(error)")
        }
        exit(0)
    }
}

// MARK: - Logger

private extension Logger {
    static let appLanguage = Logger(category: "AppLanguage")
}
