//
//  HotKey.swift
//  Ice
//

/// A combination of keys that can be used to listen for system-wide key
/// events, triggering an action whenever the combination is pressed.
struct HotKey: Codable, Hashable {
    /// The key component of the hot key.
    var key: Key
    /// The modifiers component of the hot key.
    var modifiers: Modifiers

    /// Creates a hot key with the given key and modifiers.
    /// - Parameters:
    ///   - key: The key component of the hot key.
    ///   - modifiers: The modifiers component of the hot key.
    init(key: Key, modifiers: Modifiers) {
        self.key = key
        self.modifiers = modifiers
    }
}

extension HotKey {
    /// Registers the hot key to observe system-wide key down events and
    /// returns a listener that manages the lifetime of the observation.
    func onKeyDown(_ body: @escaping () -> Void) -> Listener {
        let id = HotKeyRegistry.register(self, eventKind: .keyDown, handler: body)
        return Listener(id: id)
    }

    /// Registers the hot key to observe system-wide key up events and
    /// returns a listener that manages the lifetime of the observation.
    func onKeyUp(_ body: @escaping () -> Void) -> Listener {
        let id = HotKeyRegistry.register(self, eventKind: .keyUp, handler: body)
        return Listener(id: id)
    }
}

extension HotKey {
    /// A type that manges the lifetime of hot key observations.
    struct Listener {
        private class Context {
            private var id: UInt32?

            var isValid: Bool { id != nil }

            init(id: UInt32?) {
                self.id = id
            }

            func invalidate() {
                defer { id = nil }
                if let id { HotKeyRegistry.unregister(id) }
            }

            deinit { invalidate() }
        }

        private let context: Context

        /// A Boolean value that indicates whether the listener is
        /// currently valid.
        var isValid: Bool { context.isValid }

        fileprivate init(id: UInt32?) {
            self.context = Context(id: id)
        }

        /// Invalidates the listener, stopping the observation.
        func invalidate() {
            context.invalidate()
        }
    }
}
