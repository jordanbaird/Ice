//
//  SettingsImportPlan.swift
//  Ice
//

/// Decides which preferences are copied from another app's preferences
/// domain (the Ice app that Trincano is based on) on first launch.
///
/// The decision is pure so it can be tested without touching the
/// preferences system.
enum SettingsImportPlan {
    /// Prefix of the keys that remember where the control items sit in
    /// the menu bar, so the arrangement survives the switch.
    static let controlItemPositionPrefix = "NSStatusItem Preferred Position Ice.ControlItem."

    /// Returns the values to import.
    ///
    /// - Parameters:
    ///   - source: Every value in the source domain.
    ///   - allowedKeys: The keys the app knows how to read.
    ///   - existingKeys: Keys that already have a value in the app's own
    ///     domain. These are never overwritten.
    static func valuesToImport(
        source: [String: Any],
        allowedKeys: Set<String>,
        existingKeys: Set<String>
    ) -> [String: Any] {
        source.filter { key, _ in
            let isKnown = allowedKeys.contains(key) || key.hasPrefix(controlItemPositionPrefix)
            return isKnown && !existingKeys.contains(key)
        }
    }
}
