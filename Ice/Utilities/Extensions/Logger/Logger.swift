//
//  Logger.swift
//  Ice
//

import Foundation
import OSLog

extension Logger {
    private static let subsystem = Bundle.main.bundleIdentifier!

    /// The logger that handles logging for the status bar.
    static let statusBar = Logger(subsystem: subsystem, category: "StatusBar")

    /// The logger that handles logging for hotkeys.
    static let hotkey = Logger(subsystem: subsystem, category: "Hotkey")
}
