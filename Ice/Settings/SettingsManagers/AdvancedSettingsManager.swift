//
//  AdvancedSettingsManager.swift
//  Ice
//

import Combine
import Foundation

final class AdvancedSettingsManager: ObservableObject {
    /// A Boolean value that indicates whether the application menus should
    /// be hidden if needed to show all menu bar items.
    @Published var hideApplicationMenus: Bool = false

    /// A Boolean value that indicates whether section divider control items
    /// should be shown.
    @Published var showSectionDividers = true

    /// A Boolean value that indicates whether the Ice icon should be shown.
    @Published var showIceIcon = true

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
        Defaults.ifPresent(key: .showIceIcon, assign: &showIceIcon)
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

        $showIceIcon
            .receive(on: DispatchQueue.main)
            .sink { showIceIcon in
                Defaults.set(showIceIcon, forKey: .showIceIcon)
            }
            .store(in: &c)

        cancellables = c
    }
}

// MARK: AdvancedSettingsManager: BindingExposable
extension AdvancedSettingsManager: BindingExposable { }
