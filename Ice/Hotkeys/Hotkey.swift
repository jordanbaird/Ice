//
//  Hotkey.swift
//  Ice
//

import Combine
import OSLog

// MARK: - Hotkey

/// A combination of a key and modifiers that can be used to
/// trigger actions on system-wide key-up or key-down events.
final class Hotkey: ObservableObject {
    /// The hotkey's key combination.
    @Published var keyCombination: KeyCombination?

    /// The hotkey's action.
    let action: HotkeyAction

    /// The shared app state.
    private weak var appState: AppState?

    /// Manages the lifetime of the hotkey observation.
    private var listener: Listener?

    /// Internal observer storage.
    private var cancellable: AnyCancellable?

    /// A Boolean value that indicates whether the hotkey is enabled.
    var isEnabled: Bool { listener != nil }

    /// Creates a hotkey with the given key combination and action.
    init(keyCombination: KeyCombination?, action: HotkeyAction) {
        self.keyCombination = keyCombination
        self.action = action
        self.cancellable = $keyCombination.sink { [weak self] _ in
            Task {
                await self?.enable()
            }
        }
    }

    /// Performs the initial setup of the hotkey.
    @MainActor
    func performSetup(with appState: AppState) {
        self.appState = appState
        enable()
    }

    /// Enables the hotkey.
    @MainActor
    func enable() {
        disable()
        listener = Listener(hotkey: self, eventKind: .keyDown)
    }

    /// Disables the hotkey.
    @MainActor
    func disable() {
        listener?.invalidate()
        listener = nil
    }
}

// MARK: - Hotkey Listener

extension Hotkey {
    /// An object that manages the lifetime of a hotkey observation.
    private final class Listener {
        private weak var registry: HotkeyRegistry?
        private var id: UInt32?

        @MainActor
        init?(hotkey: Hotkey, eventKind: HotkeyRegistry.EventKind) {
            guard
                let appState = hotkey.appState,
                hotkey.keyCombination != nil
            else {
                return nil
            }
            let registry = appState.hotkeyRegistry
            let id = registry.register(hotkey: hotkey, eventKind: eventKind) { [weak appState] in
                guard let appState else {
                    return
                }
                Task {
                    await hotkey.action.perform(appState: appState)
                }
            }
            guard let id else {
                return nil
            }
            self.registry = registry
            self.id = id
        }

        deinit {
            invalidate()
        }

        func invalidate() {
            guard let id else {
                return
            }
            guard let registry else {
                Logger.hotkeys.error("Error invalidating hotkey: missing HotkeyRegistry")
                return
            }
            defer {
                self.id = nil
            }
            registry.unregister(id)
        }
    }
}

// MARK: Hotkey: Equatable
extension Hotkey: Equatable {
    static func == (lhs: Hotkey, rhs: Hotkey) -> Bool {
        lhs.keyCombination == rhs.keyCombination &&
        lhs.action == rhs.action
    }
}

// MARK: Hotkey: Hashable
extension Hotkey: Hashable {
    func hash(into hasher: inout Hasher) {
        hasher.combine(keyCombination)
        hasher.combine(action)
    }
}
