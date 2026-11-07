//
//  DurationText.swift
//  Ice
//

import Foundation

/// Text for a duration in seconds, as the settings sliders show it.
///
/// Uses the system's measurement formatting for the given locale, so the unit
/// word has the right plural form ("1 second", "2 segundos") and the number
/// uses the locale's decimal separator. (Concatenating " second"/" seconds"
/// to a number built a key that doesn't exist in the String Catalog, so the
/// unit stayed in English in Portuguese.)
enum DurationText {
    static func string(seconds: Double, locale: Locale) -> String {
        Measurement(value: seconds, unit: UnitDuration.seconds)
            .formatted(.measurement(width: .wide, usage: .asProvided).locale(locale))
    }

    /// The locale of the language the interface is actually shown in.
    static var interfaceLocale: Locale {
        Locale(identifier: Bundle.main.preferredLocalizations.first ?? "en")
    }
}
