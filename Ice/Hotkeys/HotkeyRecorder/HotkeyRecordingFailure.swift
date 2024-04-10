//
//  HotkeyRecordingFailure.swift
//  Ice
//

import Foundation

/// An error type that describes a recording failure.
enum HotkeyRecordingFailure: LocalizedError, Hashable {
    /// No modifiers were pressed.
    case noModifiers
    /// Shift was the only modifier being pressed.
    case onlyShift
    /// The given key combination is reserved by macOS.
    case reserved(KeyCombination)

    /// Description of the failure.
    var errorDescription: String? {
        switch self {
        case .noModifiers:
            return "Hotkey should include at least one modifier"
        case .onlyShift:
            return "Shift (⇧) cannot be a hotkey's only modifier"
        case let .reserved(keyCombination):
            return "Hotkey \(keyCombination.stringValue) is reserved by macOS"
        }
    }
}
