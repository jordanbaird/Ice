//
//  LocalizedErrorBox.swift
//  Ice
//

import Foundation

/// A type that wraps any error inside a LocalizedError.
///
/// If the box's underlying error is also a LocalizedError, its information
/// is passed through to the box. Otherwise, a description of the underlying
/// error is passed to the box.
struct LocalizedErrorBox: LocalizedError {
    /// The underlying error.
    let error: any Error

    var errorDescription: String? {
        (error as? any LocalizedError)?.errorDescription ?? error.localizedDescription
    }

    var failureReason: String? {
        (error as? any LocalizedError)?.failureReason
    }

    var helpAnchor: String? {
        (error as? any LocalizedError)?.helpAnchor
    }

    var recoverySuggestion: String? {
        (error as? any LocalizedError)?.recoverySuggestion
    }
}
