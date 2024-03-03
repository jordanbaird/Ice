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
    private(set) lazy var menuBarManager = MenuBarManager(appState: self)

    /// Manager for app permissions.
    private(set) lazy var permissionsManager = PermissionsManager(appState: self)

    /// Manager for app updates.
    let updatesManager = UpdatesManager()

    /// The application's current mode.
    @Published private(set) var mode: Mode = .idle

    /// The application's delegate.
    private(set) weak var appDelegate: AppDelegate?

    /// The window that contains the settings interface.
    private(set) weak var settingsWindow: NSWindow? {
        didSet {
            configureCancellables()
        }
    }

    /// The window that contains the permissions interface.
    private(set) weak var permissionsWindow: NSWindow? {
        didSet {
            configureCancellables()
        }
    }

    private var cancellables = Set<AnyCancellable>()

    /// A Boolean value that indicates whether the app is running
    /// as a SwiftUI preview.
    let isPreview: Bool = {
        #if DEBUG
        let environment = ProcessInfo.processInfo.environment
        let key = "XCODE_RUNNING_FOR_PREVIEWS"
        return environment[key] != nil
        #else
        return false
        #endif
    }()

    private init() {
        configureCancellables()
    }

    private func configureCancellables() {
        var c = Set<AnyCancellable>()

        if let settingsWindow {
            settingsWindow.publisher(for: \.isVisible)
                .sink { [weak self] isVisible in
                    self?.mode = isVisible ? .settings : .idle
                }
                .store(in: &c)
        }

        menuBarManager.objectWillChange
            .sink { [weak self] in
                self?.objectWillChange.send()
            }
            .store(in: &c)
        permissionsManager.objectWillChange
            .sink { [weak self] in
                self?.objectWillChange.send()
            }
            .store(in: &c)
        updatesManager.objectWillChange
            .sink { [weak self] in
                self?.objectWillChange.send()
            }
            .store(in: &c)

        cancellables = c
    }

    func assignAppDelegate(_ appDelegate: AppDelegate) {
        guard self.appDelegate == nil else {
            Logger.appState.warning("Multiple attempts made to assign app delegate")
            return
        }
        self.appDelegate = appDelegate
    }

    func assignSettingsWindow(_ settingsWindow: NSWindow) {
        guard self.settingsWindow == nil else {
            Logger.appState.warning("Multiple attempts made to assign settings window")
            return
        }
        self.settingsWindow = settingsWindow
    }

    func assignPermissionsWindow(_ permissionsWindow: NSWindow) {
        guard self.permissionsWindow == nil else {
            Logger.appState.warning("Multiple attempts made to assign permissions window")
            return
        }
        self.permissionsWindow = permissionsWindow
    }

    func performSetup() {
        permissionsManager.stopAllChecks()
        menuBarManager.performSetup()
        permissionsWindow?.close()
    }
}

// MARK: AppState: BindingExposable
extension AppState: BindingExposable { }

extension AppState {
    enum Mode {
        case idle
        case settings
    }
}

// MARK: - Logger
private extension Logger {
    static let appState = Logger(category: "AppState")
}
