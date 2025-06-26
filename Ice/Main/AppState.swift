//
//  AppState.swift
//  Ice
//

import Combine
import SwiftUI
import OSLog

/// The model for app-wide state.
@MainActor
final class AppState: ObservableObject {
    /// A Boolean value that indicates whether the active space is fullscreen.
    @Published private(set) var isActiveSpaceFullscreen = Bridging.isActiveSpaceFullscreen()

    /// Manager for the menu bar's appearance.
    private(set) lazy var appearanceManager = MenuBarAppearanceManager(appState: self)

    /// Manager for events received by the app.
    private(set) lazy var eventManager = EventManager(appState: self)

    /// Manager for menu bar items.
    private(set) lazy var itemManager = MenuBarItemManager(appState: self)

    /// Manager for the state of the menu bar.
    private(set) lazy var menuBarManager = MenuBarManager(appState: self)

    /// Manager for app permissions.
    private(set) lazy var permissionsManager = PermissionsManager(appState: self)

    /// Manager for the app's settings.
    private(set) lazy var settingsManager = SettingsManager(appState: self)

    /// Manager for app updates.
    private(set) lazy var updatesManager = UpdatesManager(appState: self)

    /// Manager for user notifications.
    private(set) lazy var userNotificationManager = UserNotificationManager(appState: self)

    /// Global cache for menu bar item images.
    private(set) lazy var imageCache = MenuBarItemImageCache(appState: self)

    /// Manager for menu bar item spacing.
    let spacingManager = MenuBarItemSpacingManager()

    /// Model for app-wide navigation.
    let navigationState = AppNavigationState()

    /// The app's hotkey registry.
    nonisolated let hotkeyRegistry = HotkeyRegistry()

    /// The app's delegate.
    private(set) weak var appDelegate: AppDelegate?

    /// The window that contains the settings interface.
    private(set) weak var settingsWindow: NSWindow?

    /// The window that contains the permissions interface.
    private(set) weak var permissionsWindow: NSWindow?

    /// Storage for internal observers.
    private var cancellables = Set<AnyCancellable>()

    /// Logger for the app state.
    private let logger = Logger(category: "AppState")

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

    /// A Boolean value that indicates whether the application can set the cursor
    /// in the background.
    var setsCursorInBackground: Bool {
        get { Bridging.getConnectionProperty(forKey: "SetsCursorInBackground") as? Bool ?? false }
        set { Bridging.setConnectionProperty(newValue, forKey: "SetsCursorInBackground") }
    }

    /// Configures the internal observers for the app state.
    private func configureCancellables() {
        var c = Set<AnyCancellable>()

        Publishers.Merge3(
            NSWorkspace.shared.notificationCenter
                .publisher(for: NSWorkspace.activeSpaceDidChangeNotification)
                .mapToVoid(),
            // Frontmost application change can indicate a space change from one display to
            // another, which gets ignored by NSWorkspace.activeSpaceDidChangeNotification.
            NSWorkspace.shared
                .publisher(for: \.frontmostApplication)
                .mapToVoid(),
            // Clicking into a fullscreen space from another space is also ignored.
            UniversalEventMonitor
                .publisher(for: .leftMouseDown)
                .delay(for: 0.1, scheduler: DispatchQueue.main)
                .mapToVoid()
        )
        .receive(on: DispatchQueue.main)
        .sink { [weak self] _ in
            guard let self else {
                return
            }
            isActiveSpaceFullscreen = Bridging.isActiveSpaceFullscreen()
        }
        .store(in: &c)

        NSWorkspace.shared.publisher(for: \.frontmostApplication)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] frontmostApplication in
                guard let self else {
                    return
                }
                navigationState.isAppFrontmost = frontmostApplication == .current
            }
            .store(in: &c)

        if let settingsWindow {
            settingsWindow.publisher(for: \.isVisible)
                .debounce(for: 0.05, scheduler: DispatchQueue.main)
                .sink { [weak self] isVisible in
                    guard let self else {
                        return
                    }
                    navigationState.isSettingsPresented = isVisible
                }
                .store(in: &c)
        } else {
            logger.warning("No settings window!")
        }

        Publishers.Merge(
            navigationState.$isAppFrontmost,
            navigationState.$isSettingsPresented
        )
        .debounce(for: 0.1, scheduler: DispatchQueue.main)
        .sink { [weak self] shouldUpdate in
            guard
                let self,
                shouldUpdate
            else {
                return
            }
            Task.detached {
                if ScreenCapture.cachedCheckPermissions(reset: true) {
                    await self.imageCache.updateCacheWithoutChecks(sections: MenuBarSection.Name.allCases)
                }
            }
        }
        .store(in: &c)

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

    /// Sets up the app state.
    func performSetup() {
        configureCancellables()
        permissionsManager.stopAllChecks()
        menuBarManager.performSetup()
        appearanceManager.performSetup()
        eventManager.performSetup()
        settingsManager.performSetup()
        itemManager.performSetup()
        imageCache.performSetup()
        updatesManager.performSetup()
        userNotificationManager.performSetup()
    }

    /// Assigns the app delegate to the app state.
    func assignAppDelegate(_ appDelegate: AppDelegate) {
        guard self.appDelegate == nil else {
            logger.warning("Multiple attempts made to assign app delegate")
            return
        }
        self.appDelegate = appDelegate
    }

    /// Assigns the settings window to the app state.
    func assignSettingsWindow(_ window: NSWindow) {
        guard window.identifier?.rawValue == Constants.settingsWindowID else {
            logger.warning("Window \(window.identifier?.rawValue ?? "<NIL>", privacy: .public) is not the settings window!")
            return
        }
        settingsWindow = window
        configureCancellables()
    }

    /// Assigns the permissions window to the app state.
    func assignPermissionsWindow(_ window: NSWindow) {
        guard window.identifier?.rawValue == Constants.permissionsWindowID else {
            logger.warning("Window \(window.identifier?.rawValue ?? "<NIL>", privacy: .public) is not the permissions window!")
            return
        }
        permissionsWindow = window
        configureCancellables()
    }

    /// Opens the window with the given identifier.
    func openWindow(id: String) {
        // Defer to the next run loop to prevent conflicts with SwiftUI.
        DispatchQueue.main.async {
            self.logger.debug("Opening window with id: \(id, privacy: .public)")
            EnvironmentValues().openWindow(id: id)
        }
    }

    /// Dismisses the window with the given identifier.
    func dismissWindow(id: String) {
        // Defer to the next run loop to prevent conflicts with SwiftUI.
        DispatchQueue.main.async {
            self.logger.debug("Dismissing window with id: \(id, privacy: .public)")
            EnvironmentValues().dismissWindow(id: id)
        }
    }

    /// Opens the settings window.
    func openSettingsWindow() {
        openWindow(id: Constants.settingsWindowID)
    }

    /// Dismisses the settings window.
    func dismissSettingsWindow() {
        dismissWindow(id: Constants.settingsWindowID)
    }

    /// Opens the permissions window.
    func openPermissionsWindow() {
        openWindow(id: Constants.permissionsWindowID)
    }

    /// Dismisses the permissions window.
    func dismissPermissionsWindow() {
        dismissWindow(id: Constants.permissionsWindowID)
    }

    /// Activates the app and sets its activation policy to the given value.
    func activate(withPolicy policy: NSApplication.ActivationPolicy) {

        // What follows is NOT at all straightforward, but this seems to
        // be about the only way to make app activation (mostly) reliable
        // after activation changes made in macOS 14.

        let current = NSRunningApplication.current
        let workspace = NSWorkspace.shared

        NSApp.setActivationPolicy(policy)
        NSApp.yieldActivation(to: current)

        guard var frontmost = workspace.frontmostApplication else {
            current.activate()
            return
        }

        if
            current.isActive,
            let next = workspace.menuBarOwningApplication,
            !next.isActive
        {
            next.activate(from: frontmost)
            frontmost = next
        }

        current.activate(from: frontmost)
    }

    /// Deactivates the app and sets its activation policy to the given value.
    func deactivate(withPolicy policy: NSApplication.ActivationPolicy) {
        NSApp.deactivate()
        NSApp.setActivationPolicy(policy)
    }
}

// MARK: AppState: BindingExposable
extension AppState: BindingExposable { }
