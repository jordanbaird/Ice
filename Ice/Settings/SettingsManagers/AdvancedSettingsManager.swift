//
//  AdvancedSettingsManager.swift
//  Ice
//

import Combine
import Foundation

@MainActor
final class AdvancedSettingsManager: ObservableObject {
    /// A Boolean value that indicates whether the application menus
    /// should be hidden if needed to show all menu bar items.
    @Published var hideApplicationMenus = true

    /// A Boolean value that indicates whether section divider control
    /// items should be shown.
    @Published var showSectionDividers = false

    /// A Boolean value that indicates whether the always-hidden section
    /// is enabled.
    @Published var enableAlwaysHiddenSection = false

    /// A Boolean value that indicates whether the always-hidden section
    /// can be toggled by holding down the Option key.
    @Published var canToggleAlwaysHiddenSection = true

    /// The delay before showing on hover.
    @Published var showOnHoverDelay: TimeInterval = 0.2

    /// Time interval to temporarily show items for.
    @Published var tempShowInterval: TimeInterval = 15

    /// A Boolean value that indicates whether to show all sections when
    /// the user is dragging items in the menu bar.
    @Published var showAllSectionsOnUserDrag = true
    
    /// A Boolean value that indicates whether to show all sections when
    /// the screen width is greater than showHiddenSectionWhenWidthGreaterThan
    @Published var showHiddenSectionWhenWidthGreaterThanEnabled = false
    
    /// The minimum screen size showAllSectionOnScreenSize reacts to
    @Published var showHiddenSectionWhenWidthGreaterThan: CGFloat = 3000

    /// Storage for internal observers.
    private var cancellables = Set<AnyCancellable>()

    /// The shared app state.
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
        Defaults.ifPresent(key: .enableAlwaysHiddenSection, assign: &enableAlwaysHiddenSection)
        Defaults.ifPresent(key: .canToggleAlwaysHiddenSection, assign: &canToggleAlwaysHiddenSection)
        Defaults.ifPresent(key: .showOnHoverDelay, assign: &showOnHoverDelay)
        Defaults.ifPresent(key: .tempShowInterval, assign: &tempShowInterval)
        Defaults.ifPresent(key: .showAllSectionsOnUserDrag, assign: &showAllSectionsOnUserDrag)
        Defaults.ifPresent(key: .showHiddenSectionWhenWidthGreaterThanEnabled, assign: &showHiddenSectionWhenWidthGreaterThanEnabled)
        Defaults.ifPresent(key: .showHiddenSectionWhenWidthGreaterThan, assign: &showHiddenSectionWhenWidthGreaterThan)
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

        $enableAlwaysHiddenSection
            .receive(on: DispatchQueue.main)
            .sink { enable in
                Defaults.set(enable, forKey: .enableAlwaysHiddenSection)
            }
            .store(in: &c)

        $canToggleAlwaysHiddenSection
            .receive(on: DispatchQueue.main)
            .sink { canToggle in
                Defaults.set(canToggle, forKey: .canToggleAlwaysHiddenSection)
            }
            .store(in: &c)

        $showOnHoverDelay
            .receive(on: DispatchQueue.main)
            .sink { delay in
                Defaults.set(delay, forKey: .showOnHoverDelay)
            }
            .store(in: &c)

        $tempShowInterval
            .receive(on: DispatchQueue.main)
            .sink { interval in
                Defaults.set(interval, forKey: .tempShowInterval)
            }
            .store(in: &c)

        $showAllSectionsOnUserDrag
            .receive(on: DispatchQueue.main)
            .sink { showAll in
                Defaults.set(showAll, forKey: .showAllSectionsOnUserDrag)
            }
            .store(in: &c)
        
        $showHiddenSectionWhenWidthGreaterThanEnabled
            .receive(on: DispatchQueue.main)
            .sink { showAll in
                Defaults.set(showAll, forKey: .showHiddenSectionWhenWidthGreaterThanEnabled)
            }
            .store(in: &c)
        
        $showHiddenSectionWhenWidthGreaterThan
            .receive(on: DispatchQueue.main)
            .sink { width in
                Defaults.set(width, forKey: .showHiddenSectionWhenWidthGreaterThan)
            }
            .store(in: &c)

        cancellables = c
    }
}

// MARK: AdvancedSettingsManager: BindingExposable
extension AdvancedSettingsManager: BindingExposable { }
