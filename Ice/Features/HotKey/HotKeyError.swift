//
//  HotKeyError.swift
//  Ice
//

import Foundation
import OSLog

struct HotKeyError: Error, CustomStringConvertible {
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

    func status(_ status: OSStatus) -> HotKeyError {
        HotKeyError(message: message, status: status, reason: reason)
    }

    func reason(_ reason: String) -> HotKeyError {
        HotKeyError(message: message, status: status, reason: reason)
    }
}

extension HotKeyError {
    static var installationFailed: HotKeyError {
        HotKeyError(message: "Event handler installation failed")
    }

    static var uninstallationFailed: HotKeyError {
        HotKeyError(message: "Event handler uninstallation failed")
    }

    static var registrationFailed: HotKeyError {
        HotKeyError(message: "Hot key registration failed")
    }

    static var unregistrationFailed: HotKeyError {
        HotKeyError(message: "Hot key unregistration failed")
    }

    static var systemRetrievalFailed: HotKeyError {
        HotKeyError(message: "System reserved hot key retrieval failed")
    }
}

extension Logger {
    /// Writes information about a hotkey error to the log.
    func hotKeyError(_ error: HotKeyError) {
        log(level: .error, "\(String(describing: error))")
    }
}
