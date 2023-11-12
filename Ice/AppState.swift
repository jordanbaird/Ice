//
//  AppState.swift
//  Ice
//

import Combine
import OSLog
import SwiftUI

/// The model for app-wide state.
final class AppState: ObservableObject {
    /// The shared app state singleton.
    static let shared = AppState()

    /// Manager for the state of the menu bar.
    private(set) lazy var menuBar = MenuBar(appState: self)

    /// Manager for menu bar items.
    private(set) lazy var itemManager = MenuBarItemManager(appState: self)

    /// Manager for app permissions.
    private(set) lazy var permissionsManager = PermissionsManager(appState: self)

    /// The window that contains the settings interface.
    private(set) weak var settingsWindow: NSWindow?

    private var cancellables = Set<AnyCancellable>()

    private init() {
        configureCancellables()
    }

    private func configureCancellables() {
        var c = Set<AnyCancellable>()

        // propagate changes up from child observable objects
        menuBar.objectWillChange
            .sink { [weak self] in
                self?.objectWillChange.send()
            }
            .store(in: &c)
        itemManager.objectWillChange
            .sink { [weak self] in
                self?.objectWillChange.send()
            }
            .store(in: &c)
        permissionsManager.objectWillChange
            .sink { [weak self] in
                self?.objectWillChange.send()
            }
            .store(in: &c)

        cancellables = c
    }

    /// Assigns the app state's settings window to the given window.
    ///
    /// - Important: The assignment is only made if the app state does
    ///   not currently retain a settings window. Attempting to assign
    ///   a window when one is already retained results in a warning
    ///   being logged, but otherwise has no effect.
    func assignSettingsWindow(_ settingsWindow: NSWindow) {
        guard self.settingsWindow == nil else {
            Logger.appState.warning("Multiple attempts made to assign settings window")
            return
        }
        self.settingsWindow = settingsWindow
    }
}

// MARK: AppState: BindingExposable
extension AppState: BindingExposable { }

// MARK: - Logger
private extension Logger {
    static let appState = mainSubsystem(category: "AppState")
}
