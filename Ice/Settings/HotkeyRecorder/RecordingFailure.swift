//
//  RecordingFailure.swift
//  Ice
//

import Foundation

/// An error type that describes a recording failure.
enum RecordingFailure: LocalizedError, Hashable {
    /// No modifiers were pressed.
    case noModifiers
    /// Shift was the only modifier being pressed.
    case onlyShift
    /// The given hotkey is reserved by macOS.
    case reserved(Hotkey)

    /// Description of the failure.
    var errorDescription: String? {
        switch self {
        case .noModifiers:
            return "Hotkey should include at least one modifier"
        case .onlyShift:
            return "Shift (⇧) cannot be a hotkey's only modifier"
        case .reserved(let hotkey):
            return "Hotkey \(hotkey.stringValue) is reserved by macOS"
        }
    }
}
