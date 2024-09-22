//
//  Logging.swift
//  Ice
//

import OSLog

/// Logs the given message using the specified logger and level.
func logMessage(to logger: Logger, at level: OSLogType, _ message: String) {
    logger.log(level: level, "\(message, privacy: .public)")
}

/// Logs the given informative message using the specified logger.
func logInfo(to logger: Logger, _ message: String) {
    logMessage(to: logger, at: .info, message)
}

/// Logs the given debug message using the specified logger.
func logDebugMessage(to logger: Logger, _ message: String) {
    logMessage(to: logger, at: .debug, message)
}

/// Logs the given error message using the specified logger.
func logError(to logger: Logger, _ message: String) {
    logMessage(to: logger, at: .error, message)
}

/// Logs the given warning message using the specified logger.
func logWarning(to logger: Logger, _ message: String) {
    logError(to: logger, message)
}

extension Logger {
    /// Creates a logger for Ice using the specified category.
    init(category: String) {
        self.init(subsystem: Constants.bundleIdentifier, category: category)
    }
}
