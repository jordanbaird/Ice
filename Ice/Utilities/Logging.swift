//
//  Logging.swift
//  Ice
//

import OSLog

extension Logger {
    /// Creates a logger using the specified category.
    init(category: String) {
        self.init(subsystem: Constants.bundleIdentifier, category: category)
    }
}

// MARK: - Shared Loggers

extension Logger {
    /// The default logger.
    static let `default` = Logger(.default)

    /// The logger for serialization operations.
    static let serialization = Logger(category: "Serialization")
}
