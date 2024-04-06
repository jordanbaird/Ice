//
//  AccessibilityError.swift
//  Ice
//

import AXSwift

/// An error that provides more context about an accessibility failure.
struct AccessibilityError: Error, CustomStringConvertible {
    /// A message associated with the error.
    let message: String
    /// An underlying error that was thrown by an accessibility framework, if any.
    let underlyingError: (any Error)?

    var description: String {
        var params = "message: \"\(message)\""
        if let underlyingError {
            params += ", underlyingError: \(underlyingError)"
        }
        return "\(Self.self)(\(params))"
    }

    /// Creates an error with the given message and underlying error.
    init(message: String, underlyingError: (any Error)? = nil) {
        self.message = message
        self.underlyingError = underlyingError
    }
}
