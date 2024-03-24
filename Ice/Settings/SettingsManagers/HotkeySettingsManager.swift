//
//  HotkeySettingsManager.swift
//  Ice
//

import Combine
import OSLog

final class HotkeySettingsManager: ObservableObject {
    @Published private(set) var hotkeys = HotkeyAction.allCases.map { action in
        Hotkey(keyCombination: nil, action: action)
    }

    private var cancellables = Set<AnyCancellable>()

    private let encoder = JSONEncoder()

    private let decoder = JSONDecoder()

    private(set) weak var appState: AppState?

    init(appState: AppState) {
        self.appState = appState
    }

    func performSetup() {
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
                        Logger.hotkeySettingsManager.error("Error decoding hotkey: \(error)")
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
                    hotkey.assignAppState(appState)
                    do {
                        dict[hotkey.action.rawValue] = try self.encoder.encode(hotkey.keyCombination)
                    } catch {
                        Logger.hotkeySettingsManager.error("Error encoding hotkey: \(error)")
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

// MARK: - Logger
private extension Logger {
    static let hotkeySettingsManager = Logger(category: "HotkeySettingsManager")
}
