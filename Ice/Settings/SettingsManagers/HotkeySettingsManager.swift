//
//  HotkeySettingsManager.swift
//  Ice
//

import Combine
import Foundation
import OSLog

@MainActor
final class HotkeySettingsManager: ObservableObject {
    /// All hotkeys.
    @Published private(set) var hotkeys = HotkeyAction.allCases.map { action in
        Hotkey(keyCombination: nil, action: action)
    }

    /// Encoder for hotkeys.
    private let encoder = JSONEncoder()

    /// Decoder for hotkeys.
    private let decoder = JSONDecoder()

    /// Storage for internal observers.
    private var cancellables = Set<AnyCancellable>()

    /// The shared app state.
    private(set) weak var appState: AppState?

    func performSetup(with appState: AppState) {
        self.appState = appState
        loadInitialState()
        configureCancellables()
    }

    private func loadInitialState() {
        if let dict = Defaults.dictionary(forKey: .hotkeys) as? [String: Data] {
            for hotkey in hotkeys {
                if let data = dict[hotkey.action.rawValue] {
                    do {
                        hotkey.keyCombination = try decoder.decode(KeyCombination?.self, from: data)
                    } catch {
                        Logger.serialization.error("Error decoding hotkey: \(error, privacy: .public)")
                    }
                }
            }
        }
    }

    private func configureCancellables() {
        var c = Set<AnyCancellable>()

        $hotkeys.combineLatest(Publishers.MergeMany(hotkeys.map { $0.$keyCombination }))
            .receive(on: DispatchQueue.main)
            .sink { [weak self] hotkeys, _ in
                guard
                    let self,
                    let appState
                else {
                    return
                }
                var dict = [String: Data]()
                for hotkey in hotkeys {
                    hotkey.performSetup(with: appState)
                    do {
                        dict[hotkey.action.rawValue] = try self.encoder.encode(hotkey.keyCombination)
                    } catch {
                        Logger.serialization.error("Error encoding hotkey: \(error, privacy: .public)")
                    }
                }
                Defaults.set(dict, forKey: .hotkeys)
            }
            .store(in: &c)

        cancellables = c
    }

    func hotkey(withAction action: HotkeyAction) -> Hotkey? {
        hotkeys.first { $0.action == action }
    }
}
