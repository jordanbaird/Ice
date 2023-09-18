//
//  HotkeyError.swift
//  Ice
//

import Foundation
import OSLog

/// An error that can occur during hotkey operations.
struct HotkeyError: Error, CustomStringConvertible {
    /// The message associated with the error.
    let message: String

    /// The status code associated with the error.
    let status: OSStatus?

    /// The failure reason associated with the error.
    let reason: String?

    /// Description of the error.
    var description: String {
        var components = ["[message: \(message)]"]
        if let status {
            components.insert("[status: \(status)]", at: 0)
        }
        if let reason {
            components.append("[reason: \(reason)]")
        }
        return components.joined(separator: " ")
    }

    /// Creates a hotkey error with the given message, status code,
    /// and failure reason.
    ///
    /// - Parameters:
    ///   - message: The message associated with the error.
    ///   - status: The status code associated with the error.
    ///   - reason: The failure reason associated with the error.
    init(message: String, status: OSStatus? = nil, reason: String? = nil) {
        self.message = message
        self.status = status
        self.reason = reason
    }

    /// Returns a hotkey error with the given status code.
    func status(_ status: OSStatus) -> HotkeyError {
        HotkeyError(message: message, status: status, reason: reason)
    }

    /// Returns a hotkey error with the given failure reason.
    func reason(_ reason: String) -> HotkeyError {
        HotkeyError(message: message, status: status, reason: reason)
    }
}

extension HotkeyError {
    /// A hotkey error that indicates that installing an event
    /// handler has failed.
    static var installationFailed: HotkeyError {
        HotkeyError(message: "Event handler installation failed")
    }

    /// A hotkey error that indicates that uninstalling an event
    /// handler has failed.
    static var uninstallationFailed: HotkeyError {
        HotkeyError(message: "Event handler uninstallation failed")
    }

    /// A hotkey error that indicates that registering a hotkey
    /// has failed.
    static var registrationFailed: HotkeyError {
        HotkeyError(message: "Hot key registration failed")
    }

    /// A hotkey error that indicates that unregistering a hotkey
    /// has failed.
    static var unregistrationFailed: HotkeyError {
        HotkeyError(message: "Hot key unregistration failed")
    }

    /// A hotkey error that indicates that retrieving the system
    /// reserved hotkey has failed.
    static var systemRetrievalFailed: HotkeyError {
        HotkeyError(message: "System reserved hot key retrieval failed")
    }
}

extension Logger {
    /// Writes information about a hotkey error to the log.
    func hotkeyError(_ error: HotkeyError) {
        log(level: .error, "\(String(describing: error))")
    }
}
