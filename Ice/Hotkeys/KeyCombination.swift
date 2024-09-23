//
//  KeyCombination.swift
//  Ice
//

import Carbon.HIToolbox
import Cocoa

struct KeyCombination: Hashable {
    let key: KeyCode
    let modifiers: Modifiers

    var stringValue: String {
        modifiers.symbolicValue + key.stringValue
    }

    init(key: KeyCode, modifiers: Modifiers) {
        self.key = key
        self.modifiers = modifiers
    }

    init(event: NSEvent) {
        let key = KeyCode(rawValue: Int(event.keyCode))
        let modifiers = Modifiers(nsEventFlags: event.modifierFlags)
        self.init(key: key, modifiers: modifiers)
    }
}

private func getSystemReservedKeyCombinations() -> [KeyCombination] {
    var symbolicHotkeys: Unmanaged<CFArray>?
    let status = CopySymbolicHotKeys(&symbolicHotkeys)

    guard status == noErr else {
        Logger.keyCombination.error("CopySymbolicHotKeys returned invalid status: \(status)")
        return []
    }
    guard let reservedHotkeys = symbolicHotkeys?.takeRetainedValue() as? [[String: Any]] else {
        Logger.keyCombination.error("Failed to serialize symbolic hotkeys")
        return []
    }

    return reservedHotkeys.compactMap { hotkey in
        guard
            hotkey[kHISymbolicHotKeyEnabled] as? Bool == true,
            let keyCode = hotkey[kHISymbolicHotKeyCode] as? Int,
            let modifiers = hotkey[kHISymbolicHotKeyModifiers] as? Int
        else {
            return nil
        }
        return KeyCombination(
            key: KeyCode(rawValue: keyCode),
            modifiers: Modifiers(carbonFlags: modifiers)
        )
    }
}

extension KeyCombination {
    /// Returns a Boolean value that indicates whether this key
    /// combination is reserved for system use.
    var isReservedBySystem: Bool {
        getSystemReservedKeyCombinations().contains(self)
    }
}

extension KeyCombination: Codable {
    init(from decoder: any Decoder) throws {
        var container = try decoder.unkeyedContainer()
        guard container.count == 2 else {
            throw DecodingError.dataCorrupted(
                DecodingError.Context(
                    codingPath: decoder.codingPath,
                    debugDescription: "Expected 2 encoded values, found \(container.count ?? 0)"
                )
            )
        }
        self.key = try KeyCode(rawValue: container.decode(Int.self))
        self.modifiers = try Modifiers(rawValue: container.decode(Int.self))
    }

    func encode(to encoder: any Encoder) throws {
        var container = encoder.unkeyedContainer()
        try container.encode(key.rawValue)
        try container.encode(modifiers.rawValue)
    }
}

// MARK: - Logger
private extension Logger {
    static let keyCombination = Logger(category: "KeyCombination")
}
