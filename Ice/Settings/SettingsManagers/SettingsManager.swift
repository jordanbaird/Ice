//
//  SettingsManager.swift
//  Ice
//

import Combine

@MainActor
final class SettingsManager: ObservableObject {
    /// The manager for general settings.
    let generalSettingsManager = GeneralSettingsManager()

    /// The manager for advanced settings.
    let advancedSettingsManager = AdvancedSettingsManager()

    /// The manager for hotkey settings.
    let hotkeySettingsManager = HotkeySettingsManager()

    /// Storage for internal observers.
    private var cancellables = Set<AnyCancellable>()

    func performSetup(with appState: AppState) {
        configureCancellables()
        generalSettingsManager.performSetup(with: appState)
        advancedSettingsManager.performSetup(with: appState)
        hotkeySettingsManager.performSetup(with: appState)
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
