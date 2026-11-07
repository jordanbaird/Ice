//
//  HotkeysSettings.swift
//  Ice
//

import Combine
import Foundation
import OSLog

/// Model for the app's Hotkeys settings.
@MainActor
final class HotkeysSettings: ObservableObject {
    /// The app's hotkey registry.
    let registry = HotkeyRegistry()

    /// The app's hotkeys.
    let hotkeys = HotkeyAction.allCases.map { action in
        Hotkey(action: action)
    }

    /// Encoder for properties.
    private let encoder = JSONEncoder()

    /// Decoder for properties.
    private let decoder = JSONDecoder()

    /// Storage for internal observers.
    private var cancellables = Set<AnyCancellable>()

    /// The shared app state.
    private(set) weak var appState: AppState?

    /// Performs the initial setup of the model.
    func performSetup(with appState: AppState) {
        self.appState = appState
        for hotkey in hotkeys {
            hotkey.performSetup(with: appState)
        }
        loadInitialState()
        configureCancellables()
    }

    /// Loads the model's initial state.
    private func loadInitialState() {
        guard
            let dictionary = Defaults.dictionary(forKey: .hotkeys) as? [String: Data],
            !dictionary.isEmpty
        else {
            return
        }
        for hotkey in hotkeys {
            guard let data = dictionary[hotkey.action.rawValue] else {
                continue
            }
            do {
                if let keyCombination = try decoder.decode(KeyCombination?.self, from: data) {
                    hotkey.keyCombination = keyCombination
                }
            } catch {
                Logger.serialization.error("Error decoding hotkey: \(error, privacy: .public)")
            }
        }
    }

    /// Configures the internal observers for the model.
    private func configureCancellables() {
        var c = Set<AnyCancellable>()

        for hotkey in hotkeys {
            hotkey.$keyCombination
                .encode(encoder: encoder)
                .receive(on: DispatchQueue.main)
                .sink { completion in
                    if case .failure(let error) = completion {
                        Logger.serialization.error("Error encoding hotkey: \(error, privacy: .public)")
                    }
                } receiveValue: { data in
                    withMutableCopy(of: Defaults.dictionary(forKey: .hotkeys) ?? [:]) { dictionary in
                        dictionary[hotkey.action.rawValue] = data
                        Defaults.set(dictionary, forKey: .hotkeys)
                    }
                }
                .store(in: &c)
        }

        cancellables = c
    }

    /// Returns the hotkey with the given action.
    func hotkey(withAction action: HotkeyAction) -> Hotkey? {
        hotkeys.first { $0.action == action }
    }
}
