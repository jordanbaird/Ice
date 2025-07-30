//
//  SettingsManager.swift
//  Ice
//

import Combine

@MainActor
final class SettingsManager: ObservableObject {
    /// The manager for general settings.
    let generalSettingsManager: GeneralSettingsManager

    /// The manager for advanced settings.
    let advancedSettingsManager: AdvancedSettingsManager

    /// The manager for hotkey settings.
    let hotkeySettingsManager: HotkeySettingsManager
    
    /// The manager for display-specific settings.
    let displaySettingsManager: DisplaySettingsManager

    /// Storage for internal observers.
    private var cancellables = Set<AnyCancellable>()

    /// The shared app state.
    private(set) weak var appState: AppState?

    init(appState: AppState) {
        self.generalSettingsManager = GeneralSettingsManager(appState: appState)
        self.advancedSettingsManager = AdvancedSettingsManager(appState: appState)
        self.hotkeySettingsManager = HotkeySettingsManager(appState: appState)
        self.displaySettingsManager = DisplaySettingsManager(appState: appState)
        self.appState = appState
    }

    func performSetup() {
        configureCancellables()
        generalSettingsManager.performSetup()
        advancedSettingsManager.performSetup()
        hotkeySettingsManager.performSetup()
        displaySettingsManager.performSetup()
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
        displaySettingsManager.objectWillChange
            .sink { [weak self] in
                self?.objectWillChange.send()
            }
            .store(in: &c)

        cancellables = c
    }
}

// MARK: SettingsManager: BindingExposable
extension SettingsManager: BindingExposable { }
