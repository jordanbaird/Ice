//
//  AppSettings.swift
//  Ice
//

import Combine

/// Top-level model for the app's settings.
@MainActor
final class AppSettings: ObservableObject {
    /// The model for the app's Advanced settings.
    let advanced = AdvancedSettings()

    /// The model for the app's General settings.
    let general = GeneralSettings()

    /// The model for the app's Hotkeys settings.
    let hotkeys = HotkeysSettings()

    /// Storage for internal observers.
    private var cancellables = Set<AnyCancellable>()

    /// Performs the initial setup of the settings model.
    func performSetup(with appState: AppState) {
        advanced.performSetup(with: appState)
        general.performSetup(with: appState)
        hotkeys.performSetup(with: appState)
        configureCancellables()
    }

    private func configureCancellables() {
        var c = Set<AnyCancellable>()

        advanced.objectWillChange
            .sink { [weak self] in
                self?.objectWillChange.send()
            }
            .store(in: &c)
        general.objectWillChange
            .sink { [weak self] in
                self?.objectWillChange.send()
            }
            .store(in: &c)
        hotkeys.objectWillChange
            .sink { [weak self] in
                self?.objectWillChange.send()
            }
            .store(in: &c)

        cancellables = c
    }
}
