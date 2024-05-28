//
//  Constants.swift
//  Ice
//

import Foundation

enum Constants {
    // swiftlint:disable force_unwrapping
    /// The version string in the app's bundle.
    static let appVersion = Bundle.main.versionString!

    /// The user-readable copyright string in the app's bundle.
    static let copyright = Bundle.main.copyrightString!
    // swiftlint:enable force_unwrapping

    /// The identifier for the settings window.
    static let settingsWindowID = "SettingsWindow"

    /// The identifier for the permissions window.
    static let permissionsWindowID = "PermissionsWindow"
}
