//
//  IceSettingsImporter.swift
//  Ice
//

import AppKit
import OSLog

/// Offers, once, to copy the preferences of an existing Ice installation.
///
/// This only reads the other app's preferences; nothing is written to
/// or removed from them, and nothing leaves the Mac.
@MainActor
enum IceSettingsImporter {
    private static let sourceDomain = "com.jordanbaird.Ice"
    private static let askedKey = "HasAskedToImportIceSettings"
    private static let logger = Logger(category: "IceSettingsImporter")

    /// Asks the user whether to import settings from Ice, if Ice
    /// preferences exist and the question hasn't been asked before.
    static func offerImportIfNeeded() {
        let defaults = UserDefaults.standard
        guard !defaults.bool(forKey: askedKey) else {
            return
        }
        defaults.set(true, forKey: askedKey)

        guard let source = readSourceValues(), !source.isEmpty else {
            return
        }

        NSApp.activate()
        let alert = NSAlert()
        alert.messageText = String(localized: "Import your settings from Ice?")
        alert.informativeText = String(localized: "Trincano found settings from an existing Ice installation. They will be copied to Trincano; Ice itself is not changed. Nothing leaves your Mac.")
        alert.addButton(withTitle: String(localized: "Import Settings"))
        alert.addButton(withTitle: String(localized: "Start Fresh"))
        guard alert.runModal() == .alertFirstButtonReturn else {
            return
        }

        // Only the app's own domain counts: dictionaryRepresentation() also
        // includes the global and registration domains.
        let existing = Set(defaults.persistentDomain(forName: Constants.bundleIdentifier)?.keys.map { $0 } ?? [])
        let values = SettingsImportPlan.valuesToImport(
            source: source,
            allowedKeys: Set(Defaults.Key.allCases.map(\.rawValue)),
            existingKeys: existing
        )
        for (key, value) in values {
            defaults.set(value, forKey: key)
        }
        logger.info("Imported \(values.count, privacy: .public) settings from Ice")
    }

    private static func readSourceValues() -> [String: Any]? {
        guard
            let keys = CFPreferencesCopyKeyList(
                sourceDomain as CFString,
                kCFPreferencesCurrentUser,
                kCFPreferencesAnyHost
            ) as? [String],
            let values = CFPreferencesCopyMultiple(
                keys as CFArray,
                sourceDomain as CFString,
                kCFPreferencesCurrentUser,
                kCFPreferencesAnyHost
            ) as? [String: Any]
        else {
            return nil
        }
        return values
    }
}
