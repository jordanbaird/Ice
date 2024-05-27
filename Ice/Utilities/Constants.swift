//
//  Constants.swift
//  Ice
//

import Foundation

enum Constants {
    /// The version string in the app's bundle.
    static let appVersion = Bundle.main.versionString! // swiftlint:disable:this force_unwrapping

    /// A user-readable copyright string formatted with non-breaking
    /// spaces for display in the user interface.
    static let copyright: String = "Copyright\u{00A0}©\u{00A0}2024 Jordan\u{00A0}Baird. All\u{00A0}Rights\u{00A0}Reserved." // U+00A0 'NO-BREAK SPACE'

    /// The identifier for the settings window.
    static let settingsWindowID = "SettingsWindow"

    /// The identifier for the permissions window.
    static let permissionsWindowID = "PermissionsWindow"
}
