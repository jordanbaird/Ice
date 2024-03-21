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

    /// The secondary action to perform when a control item is clicked.
    @Published var secondaryAction: SecondaryAction = .toggleAlwaysHiddenSection

    /// The modifier key that is used to trigger the secondary action
    /// of all control items.
    @Published var secondaryActionModifier: Modifiers = .option

    /// A Boolean value that indicates whether clicking an empty space
    /// in the menu bar while holding down the secondary action modifier
    /// should perform the secondary action.
    @Published var performSecondaryActionInEmptySpace = true

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
        Defaults.ifPresent(key: .performSecondaryActionInEmptySpace, assign: &performSecondaryActionInEmptySpace)
        Defaults.ifPresent(key: .secondaryAction) { rawValue in
            if let action = SecondaryAction(rawValue: rawValue) {
                secondaryAction = action
            }
        }
        Defaults.ifPresent(key: .secondaryActionModifier) { rawValue in
            secondaryActionModifier = Modifiers(rawValue: rawValue)
        }
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

        $secondaryAction
            .receive(on: DispatchQueue.main)
            .sink { action in
                Defaults.set(action.rawValue, forKey: .secondaryAction)
            }
            .store(in: &c)

        $secondaryActionModifier
            .receive(on: DispatchQueue.main)
            .sink { modifier in
                Defaults.set(modifier.rawValue, forKey: .secondaryActionModifier)
            }
            .store(in: &c)

        $performSecondaryActionInEmptySpace
            .receive(on: DispatchQueue.main)
            .sink { shouldPerform in
                Defaults.set(shouldPerform, forKey: .performSecondaryActionInEmptySpace)
            }
            .store(in: &c)

        cancellables = c
    }
}

// MARK: AdvancedSettingsManager: BindingExposable
extension AdvancedSettingsManager: BindingExposable { }
