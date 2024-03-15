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
        if let data = Defaults.data(forKey: .hotkeys) {
            do {
                hotkeys = try decoder.decode([Hotkey].self, from: data)
            } catch {
                Logger.hotkeySettingsManager.error("Error decoding hotkeys: \(error)")
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
                for hotkey in hotkeys {
                    hotkey.assignAppState(appState)
                }
                do {
                    let data = try encoder.encode(hotkeys)
                    Defaults.set(data, forKey: .hotkeys)
                } catch {
                    Logger.hotkeySettingsManager.error("Error encoding hotkeys: \(error)")
                }
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
