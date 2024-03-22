//
//  AdvancedSettingsManager.swift
//  Ice
//

import Combine
import Foundation

final class AdvancedSettingsManager: ObservableObject {
    /// Valid modifier keys that can be used to trigger the secondary
    /// action of all control items.
    static let validSecondaryActionModifiers: [Modifiers] = [.control, .option, .shift]

    /// A Boolean value that indicates whether the application menus
    /// should be hidden if needed to show all menu bar items.
    @Published var hideApplicationMenus = true

    /// A Boolean value that indicates whether section divider control
    /// items should be shown.
    @Published var showSectionDividers = false

    /// A Boolean value that indicates whether the always-hidden section
    /// can be toggled by holding down the Option key.
    @Published var canToggleAlwaysHiddenSection = true

    private var cancellables = Set<AnyCancellable>()

    private(set) weak var appState: AppState?

    init(appState: AppState) {
        self.appState = appState
    }

    func performSetup() {
        loadInitialState()
        configureCancellables()
    }

    private func loadInitialState() {
        Defaults.ifPresent(key: .hideApplicationMenus, assign: &hideApplicationMenus)
        Defaults.ifPresent(key: .showSectionDividers, assign: &showSectionDividers)
        Defaults.ifPresent(key: .canToggleAlwaysHiddenSection, assign: &canToggleAlwaysHiddenSection)
    }

    private func configureCancellables() {
        var c = Set<AnyCancellable>()

        $hideApplicationMenus
            .receive(on: DispatchQueue.main)
            .sink { shouldHide in
                Defaults.set(shouldHide, forKey: .hideApplicationMenus)
            }
            .store(in: &c)

        $showSectionDividers
            .receive(on: DispatchQueue.main)
            .sink { shouldShow in
                Defaults.set(shouldShow, forKey: .showSectionDividers)
            }
            .store(in: &c)

        $canToggleAlwaysHiddenSection
            .receive(on: DispatchQueue.main)
            .sink { canToggle in
                Defaults.set(canToggle, forKey: .canToggleAlwaysHiddenSection)
            }
            .store(in: &c)

        cancellables = c
    }
}

// MARK: AdvancedSettingsManager: BindingExposable
extension AdvancedSettingsManager: BindingExposable { }
