//
//  AdvancedSettings.swift
//  Ice
//

import Combine
import SwiftUI

// MARK: - AdvancedSettings

/// Model for the app's Advanced settings.
@MainActor
final class AdvancedSettings: ObservableObject {
    /// A Boolean value that indicates whether the always-hidden section
    /// is enabled.
    @Published var enableAlwaysHiddenSection = false

    /// A Boolean value that indicates whether to show all sections when
    /// the user is dragging items in the menu bar.
    @Published var showAllSectionsOnUserDrag = true

    /// The display style for section divider control items.
    @Published var sectionDividerStyle: SectionDividerStyle = .noDivider

    /// A Boolean value that indicates whether the application menus
    /// should be hidden if needed to show all menu bar items.
    @Published var hideApplicationMenus = true

    /// A Boolean value that indicates whether to show a context menu
    /// when the user right-clicks the menu bar.
    @Published var enableSecondaryContextMenu = true

    /// The delay before showing on hover.
    @Published var showOnHoverDelay: TimeInterval = 0.2

    /// Time interval to temporarily show items for.
    @Published var tempShowInterval: TimeInterval = 15

    /// Storage for internal observers.
    private var cancellables = Set<AnyCancellable>()

    /// The shared app state.
    private(set) weak var appState: AppState?

    /// Performs the initial setup of the model.
    func performSetup(with appState: AppState) {
        self.appState = appState
        loadInitialState()
        configureCancellables()
    }

    /// Loads the model's initial state.
    private func loadInitialState() {
        Defaults.ifPresent(key: .enableAlwaysHiddenSection, assign: &enableAlwaysHiddenSection)
        Defaults.ifPresent(key: .showAllSectionsOnUserDrag, assign: &showAllSectionsOnUserDrag)
        Defaults.ifPresent(key: .hideApplicationMenus, assign: &hideApplicationMenus)
        Defaults.ifPresent(key: .enableSecondaryContextMenu, assign: &enableSecondaryContextMenu)
        Defaults.ifPresent(key: .showOnHoverDelay, assign: &showOnHoverDelay)
        Defaults.ifPresent(key: .tempShowInterval, assign: &tempShowInterval)

        Defaults.ifPresent(key: .sectionDividerStyle) { rawValue in
            if let style = SectionDividerStyle(rawValue: rawValue) {
                sectionDividerStyle = style
            }
        }
    }

    /// Configures the internal observers for the model.
    private func configureCancellables() {
        var c = Set<AnyCancellable>()

        $enableAlwaysHiddenSection
            .receive(on: DispatchQueue.main)
            .sink { enable in
                Defaults.set(enable, forKey: .enableAlwaysHiddenSection)
            }
            .store(in: &c)

        $showAllSectionsOnUserDrag
            .receive(on: DispatchQueue.main)
            .sink { showAll in
                Defaults.set(showAll, forKey: .showAllSectionsOnUserDrag)
            }
            .store(in: &c)

        $sectionDividerStyle
            .receive(on: DispatchQueue.main)
            .sink { style in
                Defaults.set(style.rawValue, forKey: .sectionDividerStyle)
            }
            .store(in: &c)

        $hideApplicationMenus
            .receive(on: DispatchQueue.main)
            .sink { shouldHide in
                Defaults.set(shouldHide, forKey: .hideApplicationMenus)
            }
            .store(in: &c)

        $enableSecondaryContextMenu
            .receive(on: DispatchQueue.main)
            .sink { enable in
                Defaults.set(enable, forKey: .enableSecondaryContextMenu)
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

        cancellables = c
    }
}

// MARK: - SectionDividerStyle

enum SectionDividerStyle: Int, CaseIterable, Identifiable {
    case noDivider = 0
    case chevron = 1

    var id: Int { rawValue }

    /// Localized string key representation.
    var localized: LocalizedStringKey {
        switch self {
        case .noDivider: "None"
        case .chevron: "Chevron"
        }
    }
}
