//
//  Hotkey.swift
//  Ice
//

import Carbon.HIToolbox
import OSLog

/// A combination of keys that can be used to listen for system-wide key
/// events, triggering an action whenever the combination is pressed.
struct Hotkey: Codable, Hashable {
    /// The key component of the hot key.
    var key: Key
    /// The modifiers component of the hot key.
    var modifiers: Modifiers

    var stringValue: String {
        key.stringValue + modifiers.stringValue
    }

    /// Creates a hot key with the given key and modifiers.
    /// - Parameters:
    ///   - key: The key component of the hot key.
    ///   - modifiers: The modifiers component of the hot key.
    init(key: Key, modifiers: Modifiers) {
        self.key = key
        self.modifiers = modifiers
    }
}

extension Hotkey {
    /// An array hotkeys reserved by the system.
    static var reservedHotkeys: [Hotkey] {
        var symbolicHotkeys: Unmanaged<CFArray>?
        let status = CopySymbolicHotKeys(&symbolicHotkeys)
        guard status == noErr else {
            Logger.hotkey.hotkeyError(
                HotkeyError.systemRetrievalFailed
                    .reason("CopySymbolicHotKeys returned invalid status")
                    .status(status)
            )
            return []
        }
        guard let reservedHotkeys = symbolicHotkeys?.takeRetainedValue() as? [[String: Any]] else {
            Logger.hotkey.hotkeyError(
                HotkeyError.systemRetrievalFailed
                    .reason("Failed to serialize symbolic hotkeys")
            )
            return []
        }
        return reservedHotkeys.compactMap { hotkey in
            guard
                hotkey[kHISymbolicHotKeyEnabled] as? Bool == true,
                let keyCode = hotkey[kHISymbolicHotKeyCode] as? Int,
                let carbonModifiers = hotkey[kHISymbolicHotKeyModifiers] as? Int
            else {
                return nil
            }
            return Hotkey(
                key: Key(rawValue: keyCode),
                modifiers: Modifiers(carbonFlags: carbonModifiers)
            )
        }
    }

    /// Returns a Boolean value that indicates whether the given key-modifier
    /// combination is reserved for system use.
    ///
    /// - Parameters:
    ///   - key: The key to look for in the system.
    ///   - modifiers: The modifiers to look for in the system.
    ///
    /// - Returns: `true` if the system reserves the given key-modifier combination
    ///   for its own use. `false` otherwise.
    static func isReservedBySystem(key: Key, modifiers: Modifiers) -> Bool {
        let hotkey = Hotkey(key: key, modifiers: modifiers)
        return reservedHotkeys.contains(hotkey)
    }
}

extension Hotkey {
    /// Registers the hot key to observe system-wide key down events and
    /// returns a listener that manages the lifetime of the observation.
    func onKeyDown(_ body: @escaping () -> Void) -> Listener {
        let id = HotkeyRegistry.register(self, eventKind: .keyDown, handler: body)
        return Listener(id: id)
    }

    /// Registers the hot key to observe system-wide key up events and
    /// returns a listener that manages the lifetime of the observation.
    func onKeyUp(_ body: @escaping () -> Void) -> Listener {
        let id = HotkeyRegistry.register(self, eventKind: .keyUp, handler: body)
        return Listener(id: id)
    }
}

extension Hotkey {
    /// A type that manges the lifetime of hot key observations.
    struct Listener {
        private class HotkeyListenerContext {
            private var id: UInt32?

            var isValid: Bool { id != nil }

            init(id: UInt32?) {
                self.id = id
            }

            func invalidate() {
                defer { id = nil }
                if let id { HotkeyRegistry.unregister(id) }
            }

            deinit { invalidate() }
        }

        private let context: HotkeyListenerContext

        /// A Boolean value that indicates whether the listener is
        /// currently valid.
        var isValid: Bool { context.isValid }

        fileprivate init(id: UInt32?) {
            self.context = HotkeyListenerContext(id: id)
        }

        /// Invalidates the listener, stopping the observation.
        func invalidate() {
            context.invalidate()
        }
    }
}
