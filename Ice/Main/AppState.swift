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

    /// Manager for app updates.
    let updatesManager = UpdatesManager()

    /// Global hotkey registry.
    let hotkeyRegistry = HotkeyRegistry()

    /// The application's delegate.
    private(set) weak var appDelegate: AppDelegate?

    /// The window that contains the settings interface.
    private(set) weak var settingsWindow: NSWindow?

    /// The window that contains the permissions interface.
    private(set) weak var permissionsWindow: NSWindow?

    /// A Boolean value that indicates whether the user has interacted with
    /// the menu bar, preventing the "ShowOnHover" feature from activating.
    var showOnHoverPreventedByUserInteraction = false

    /// A Boolean value that indicates whether the app is running as a
    /// SwiftUI preview.
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
        migrateHotkeys()
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

// MARK: Migrate Hotkeys
extension AppState {
    /// Migrates the user's saved hotkeys from the old method of storing
    /// them in their corresponding menu bar sections to the new method
    /// of storing them as stand-alone data.
    private func migrateHotkeys() {
        // deserialize the stored sections into an array of dictionaries
        let sectionsArray: [[String: Any]]
        do {
            guard
                let data = Defaults.data(forKey: .sections),
                let array = try JSONSerialization.jsonObject(with: data) as? [[String: Any]]
            else {
                Logger.appState.error("Error deserializing menu bar sections")
                return
            }
            sectionsArray = array
        } catch {
            Logger.appState.error("Error migrating hotkeys: \(error)")
            return
        }
        // get the hotkey data from the hidden and always hidden sections,
        // if available, and create equivalent key combinations to assign
        // to the corresponding hotkeys
        for name: MenuBarSection.Name in [.hidden, .alwaysHidden] {
            guard
                let sectionDict = sectionsArray.first(where: { $0["name"] as? String == name.rawValue }),
                let hotkeyDict = sectionDict["hotkey"] as? [String: Int],
                let key = hotkeyDict["key"],
                let modifiers = hotkeyDict["modifiers"]
            else {
                continue
            }
            let keyCombination = KeyCombination(
                key: KeyCode(rawValue: key),
                modifiers: Modifiers(rawValue: modifiers)
            )
            let hotkeySettingsManager = settingsManager.hotkeySettingsManager
            if case .hidden = name {
                if let hotkey = hotkeySettingsManager.hotkey(withAction: .toggleHiddenSection) {
                    hotkey.keyCombination = keyCombination
                }
            } else if case .alwaysHidden = name {
                if let hotkey = hotkeySettingsManager.hotkey(withAction: .toggleAlwaysHiddenSection) {
                    hotkey.keyCombination = keyCombination
                }
            }
        }
    }
}

// MARK: AppState: BindingExposable
extension AppState: BindingExposable { }

// MARK: - Logger
private extension Logger {
    static let appState = Logger(category: "AppState")
}
