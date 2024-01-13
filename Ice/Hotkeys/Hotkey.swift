//
//  Hotkey.swift
//  Ice
//

import Carbon.HIToolbox
import Cocoa
import OSLog

/// A combination of keys that can be used to trigger actions
/// on system-wide key-up or key-down events.
struct Hotkey: Codable, Hashable {
    /// The key component of the hotkey.
    var key: Key

    /// The modifiers component of the hotkey.
    var modifiers: Modifiers

    /// A string representation of the hotkey.
    var stringValue: String {
        key.stringValue + modifiers.stringValue
    }

    /// Creates a hotkey with the given key and modifiers.
    ///
    /// - Parameters:
    ///   - key: The key component of the hotkey.
    ///   - modifiers: The modifiers component of the hotkey.
    init(key: Key, modifiers: Modifiers) {
        self.key = key
        self.modifiers = modifiers
    }

    /// Creates a hotkey from the key code and modifier flags
    /// in the given event.
    init(event: NSEvent) {
        self.init(
            key: Key(rawValue: Int(event.keyCode)),
            modifiers: Modifiers(nsEventFlags: event.modifierFlags)
        )
    }
}

extension Hotkey {
    /// An array hotkeys reserved by the system.
    static var reservedHotkeys: [Hotkey] {
        var symbolicHotkeys: Unmanaged<CFArray>?
        let status = CopySymbolicHotKeys(&symbolicHotkeys)
        guard status == noErr else {
            Logger.hotkey.error("CopySymbolicHotKeys returned invalid status \(status)")
            return []
        }
        guard let reservedHotkeys = symbolicHotkeys?.takeRetainedValue() as? [[String: Any]] else {
            Logger.hotkey.error("Failed to serialize symbolic hotkeys")
            return []
        }
        return reservedHotkeys.compactMap { hotkey in
            guard
                hotkey[kHISymbolicHotKeyEnabled] as? Bool == true,
                let carbonKeyCode = hotkey[kHISymbolicHotKeyCode] as? Int,
                let carbonModifiers = hotkey[kHISymbolicHotKeyModifiers] as? Int
            else {
                return nil
            }
            return Hotkey(
                key: Key(rawValue: carbonKeyCode),
                modifiers: Modifiers(carbonFlags: carbonModifiers)
            )
        }
    }

    /// Returns a Boolean value that indicates whether this hotkey
    /// is reserved for system use.
    var isReservedBySystem: Bool {
        Self.reservedHotkeys.contains(self)
    }
}

extension Hotkey {
    /// Registers the hotkey to observe system-wide key down events and
    /// returns a listener that manages the lifetime of the observation.
    func onKeyDown(_ body: @escaping () -> Void) -> Listener {
        let id = HotkeyRegistry.register(
            hotkey: self,
            eventKind: .keyDown,
            handler: body
        )
        return Listener(id: id)
    }

    /// Registers the hotkey to observe system-wide key up events and
    /// returns a listener that manages the lifetime of the observation.
    func onKeyUp(_ body: @escaping () -> Void) -> Listener {
        let id = HotkeyRegistry.register(
            hotkey: self,
            eventKind: .keyUp,
            handler: body
        )
        return Listener(id: id)
    }
}

extension Hotkey {
    /// A type that manges the lifetime of hotkey observations.
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

// MARK: - Logger
private extension Logger {
    static let hotkey = Logger(category: "Hotkey")
}
