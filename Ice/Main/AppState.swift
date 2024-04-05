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

    private var cancellables = Set<AnyCancellable>()

    /// Manager for events received by the app.
    private(set) lazy var eventManager = EventManager(appState: self)

    /// Manager for the state of the menu bar.
    private(set) lazy var menuBarManager = MenuBarManager(appState: self)

    /// Manager for app permissions.
    private(set) lazy var permissionsManager = PermissionsManager(appState: self)

    /// Manager for the app's settings.
    private(set) lazy var settingsManager = SettingsManager(appState: self)

    /// Manager for screen capture operations.
    let screenCaptureManager = ScreenCaptureManager()

    /// Manager for app updates.
    let updatesManager = UpdatesManager()

    /// The app's hotkey registry.
    let hotkeyRegistry = HotkeyRegistry()

    /// The app's delegate.
    private(set) weak var appDelegate: AppDelegate?

    /// The window that contains the settings interface.
    private(set) weak var settingsWindow: NSWindow?

    /// The window that contains the permissions interface.
    private(set) weak var permissionsWindow: NSWindow?

    /// A Boolean value that indicates whether the user has interacted with the menu
    /// bar, preventing the "ShowOnHover" feature from activating.
    var showOnHoverIsPreventedByUserInteraction = false

    /// A Boolean value that indicates whether the app is running as a SwiftUI preview.
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
        MigrationManager(appState: self).migrateAll()
        configureCancellables()
    }

    private func configureCancellables() {
        var c = Set<AnyCancellable>()

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
        settingsManager.objectWillChange
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

    func performSetup() {
        permissionsManager.stopAllChecks()
        eventManager.performSetup()
        menuBarManager.performSetup()
        settingsManager.performSetup()
        permissionsWindow?.close()
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
        configureCancellables()
    }

    func assignPermissionsWindow(_ permissionsWindow: NSWindow) {
        guard self.permissionsWindow == nil else {
            Logger.appState.warning("Multiple attempts made to assign permissions window")
            return
        }
        self.permissionsWindow = permissionsWindow
    }

    /// Activates the app and sets its activation policy to the given value.
    func activate(withPolicy policy: NSApplication.ActivationPolicy) {
        if let frontApp = NSWorkspace.shared.frontmostApplication {
            NSRunningApplication.current.activate(from: frontApp)
        } else {
            NSApp.activate()
        }
        NSApp.setActivationPolicy(policy)
    }

    /// Deactivates the app and sets its activation policy to the given value.
    func deactivate(withPolicy policy: NSApplication.ActivationPolicy) {
        if let nextApp = NSWorkspace.shared.runningApplications.first(where: { $0 != .current }) {
            NSApp.yieldActivation(to: nextApp)
        } else {
            NSApp.deactivate()
        }
        NSApp.setActivationPolicy(policy)
    }
}

// MARK: AppState: BindingExposable
extension AppState: BindingExposable { }

// MARK: - Logger
private extension Logger {
    static let appState = Logger(category: "AppState")
}
