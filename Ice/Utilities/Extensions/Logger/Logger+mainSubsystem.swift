//
//  Logger+mainSubsystem.swift
//  Ice
//

import Foundation
import OSLog

extension Logger {
    private static let subsystem = Bundle.main.bundleIdentifier!

    /// Returns a logger using the specified category, with a subsystem
    /// derived from the application's main bundle identifier.
    static func mainSubsystem(category: String) -> Logger {
        Logger(subsystem: subsystem, category: category)
    }
}
