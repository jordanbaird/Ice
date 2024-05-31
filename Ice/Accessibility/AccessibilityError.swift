//
//  AccessibilityError.swift
//  Ice
//

/// An error that provides more context about an accessibility failure.
struct AccessibilityError: Error, CustomStringConvertible {
    /// A message associated with the error.
    var message: String
    /// An underlying error that was thrown by an accessibility framework, if any.
    var underlyingError: (any Error)?

    var description: String {
        var description = message
        if let underlyingError {
            description += " (\(underlyingError))"
        }
        return description
    }
}
