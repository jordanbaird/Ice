//
//  LocalizedErrorWrapper.swift
//  Ice
//

import Foundation

/// A type that wraps the information of any error inside a `LocalizedError`.
///
/// If the error used to initialize the box is also a `LocalizedError`, its
/// information is passed through to the box. Otherwise, a description of the
/// error is passed to the wrapper.
struct LocalizedErrorWrapper: LocalizedError {
    let errorDescription: String?
    let failureReason: String?
    let helpAnchor: String?
    let recoverySuggestion: String?

    /// Creates a wrapper with the given error.
    init(_ error: any Error) {
        if let error = error as? any LocalizedError {
            self.errorDescription = error.errorDescription
            self.failureReason = error.failureReason
            self.helpAnchor = error.helpAnchor
            self.recoverySuggestion = error.recoverySuggestion
        } else {
            self.errorDescription = error.localizedDescription
            self.failureReason = nil
            self.helpAnchor = nil
            self.recoverySuggestion = nil
        }
    }
}
