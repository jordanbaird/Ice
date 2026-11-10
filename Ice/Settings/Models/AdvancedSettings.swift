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

    /// Whether Ice draws its own camera and microphone indicator while it is hiding items.
    ///
    /// Control Centre's own is not drawn at all while anything is concealed, and no allowlist can
    /// spare it, so without this there is nothing on the bar to say the camera is on (macOS 27).
    @Published var showCaptureIndicator = true

    /// How Ice hides applications' items on macOS 27.
    @Published var macOS27HidingMethod: MacOS27HidingMethod = .nativeAllowList

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
        Defaults.ifPresent(key: .showCaptureIndicator, assign: &showCaptureIndicator)
        Defaults.ifPresent(key: .tempShowInterval, assign: &tempShowInterval)

        Defaults.ifPresent(key: .macOS27HidingMethod) { (rawValue: String) in
            if let method = MacOS27HidingMethod(rawValue: rawValue) {
                macOS27HidingMethod = method
            }
        }

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

        $showCaptureIndicator
            .receive(on: DispatchQueue.main)
            .sink { show in
                Defaults.set(show, forKey: .showCaptureIndicator)
            }
            .store(in: &c)

        $macOS27HidingMethod
            .receive(on: DispatchQueue.main)
            .sink { method in
                Defaults.set(method.rawValue, forKey: .macOS27HidingMethod)
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

// MARK: - MacOS27HidingMethod

/// How Ice hides applications' items on macOS 27.
enum MacOS27HidingMethod: String, CaseIterable, Identifiable {
    /// macOS's own "Allow in the Menu Bar" switch for each hidden application
    /// (see `NativeAllowListConcealer27`).
    case nativeAllowList

    /// MenuBarAgent's assessment mode (see `MenuBarAssessmentAssertion27`), which also removes
    /// Control Centre's modules and ignores clicks on system items while it is in force.
    case assessmentMode

    var id: String { rawValue }

    /// Localized string key representation.
    var localized: LocalizedStringKey {
        switch self {
        case .nativeAllowList: "Allow in the Menu Bar"
        case .assessmentMode: "Assessment mode"
        }
    }
}
