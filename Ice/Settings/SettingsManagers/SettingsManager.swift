//
//  SettingsManager.swift
//  Ice
//

import Combine

final class SettingsManager: ObservableObject {
    let generalSettingsManager: GeneralSettingsManager

    let advancedSettingsManager: AdvancedSettingsManager

    let hotkeySettingsManager: HotkeySettingsManager

    private(set) weak var appState: AppState?

    private var cancellables = Set<AnyCancellable>()

    init(appState: AppState) {
        self.generalSettingsManager = GeneralSettingsManager(appState: appState)
        self.advancedSettingsManager = AdvancedSettingsManager(appState: appState)
        self.hotkeySettingsManager = HotkeySettingsManager(appState: appState)
        self.appState = appState
    }

    func performSetup() {
        configureCancellables()
        generalSettingsManager.performSetup()
        advancedSettingsManager.performSetup()
        hotkeySettingsManager.performSetup()
    }

    private func configureCancellables() {
        var c = Set<AnyCancellable>()

        generalSettingsManager.objectWillChange
            .sink { [weak self] in
                self?.objectWillChange.send()
            }
            .store(in: &c)
        advancedSettingsManager.objectWillChange
            .sink { [weak self] in
                self?.objectWillChange.send()
            }
            .store(in: &c)
        hotkeySettingsManager.objectWillChange
            .sink { [weak self] in
                self?.objectWillChange.send()
            }
            .store(in: &c)

        cancellables = c
    }
}

// MARK: SettingsManager: BindingExposable
extension SettingsManager: BindingExposable { }
