//
//  HotkeyError.swift
//  Ice
//

import Foundation
import OSLog

struct HotkeyError: Error, CustomStringConvertible {
    let message: String

    let status: OSStatus?

    let reason: String?

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

    init(message: String, status: OSStatus? = nil, reason: String? = nil) {
        self.message = message
        self.status = status
        self.reason = reason
    }

    func status(_ status: OSStatus) -> HotkeyError {
        HotkeyError(message: message, status: status, reason: reason)
    }

    func reason(_ reason: String) -> HotkeyError {
        HotkeyError(message: message, status: status, reason: reason)
    }
}

extension HotkeyError {
    static var installationFailed: HotkeyError {
        HotkeyError(message: "Event handler installation failed")
    }

    static var uninstallationFailed: HotkeyError {
        HotkeyError(message: "Event handler uninstallation failed")
    }

    static var registrationFailed: HotkeyError {
        HotkeyError(message: "Hot key registration failed")
    }

    static var unregistrationFailed: HotkeyError {
        HotkeyError(message: "Hot key unregistration failed")
    }

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
