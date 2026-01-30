//
//  AppState.swift
//  Ice
//

import Combine
import SwiftUI

/// The model for app-wide state.
@MainActor
final class AppState: ObservableObject {
    /// A Boolean value that indicates whether the active space is fullscreen.
    @Published private(set) var isActiveSpaceFullscreen = Bridging.isSpaceFullscreen(Bridging.activeSpaceID)

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

    /// A Boolean value that indicates whether the "ShowOnHover" feature is prevented.
    private(set) var isShowOnHoverPrevented = false

    /// Storage for internal observers.
    private var cancellables = Set<AnyCancellable>()

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
            isActiveSpaceFullscreen = Bridging.isSpaceFullscreen(Bridging.activeSpaceID)
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
            Logger.appState.warning("No settings window!")
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
		DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
			self?.updatesManager.startUpdater()
		}
        userNotificationManager.performSetup()
    }

    /// Assigns the app delegate to the app state.
    func assignAppDelegate(_ appDelegate: AppDelegate) {
        guard self.appDelegate == nil else {
            Logger.appState.warning("Multiple attempts made to assign app delegate")
            return
        }
        self.appDelegate = appDelegate
    }

    /// Assigns the settings window to the app state.
    func assignSettingsWindow(_ window: NSWindow) {
        guard window.identifier?.rawValue == Constants.settingsWindowID else {
            Logger.appState.warning("Window \(window.identifier?.rawValue ?? "<NIL>") is not the settings window!")
            return
        }
        settingsWindow = window
        configureCancellables()
    }

    /// Assigns the permissions window to the app state.
    func assignPermissionsWindow(_ window: NSWindow) {
        guard window.identifier?.rawValue == Constants.permissionsWindowID else {
            Logger.appState.warning("Window \(window.identifier?.rawValue ?? "<NIL>") is not the permissions window!")
            return
        }
        permissionsWindow = window
        configureCancellables()
    }

    /// Opens the settings window.
    func openSettingsWindow() {
        with(EnvironmentValues()) { environment in
            environment.openWindow(id: Constants.settingsWindowID)
        }
    }

    /// Dismisses the settings window.
    func dismissSettingsWindow() {
        with(EnvironmentValues()) { environment in
            environment.dismissWindow(id: Constants.settingsWindowID)
        }
    }

    /// Opens the permissions window.
    func openPermissionsWindow() {
        with(EnvironmentValues()) { environment in
            environment.openWindow(id: Constants.permissionsWindowID)
        }
    }

    /// Dismisses the permissions window.
    func dismissPermissionsWindow() {
        with(EnvironmentValues()) { environment in
            environment.dismissWindow(id: Constants.permissionsWindowID)
        }
    }

    /// Activates the app and sets its activation policy to the given value.
    func activate(withPolicy policy: NSApplication.ActivationPolicy) {
        // Store whether the app has previously activated inside an internal
        // context to keep it isolated.
        enum Context {
            static let hasActivated = ObjectStorage<Bool>()
        }

        func activate() {
            if let frontApp = NSWorkspace.shared.frontmostApplication {
                NSRunningApplication.current.activate(from: frontApp)
            } else {
                NSApp.activate()
            }
            NSApp.setActivationPolicy(policy)
        }

        if Context.hasActivated.value(for: self) == true {
            activate()
        } else {
            Context.hasActivated.set(true, for: self)
            Logger.appState.debug("First time activating app, so going through Dock")
            // Hack to make sure the app properly activates for the first time.
            NSRunningApplication.runningApplications(withBundleIdentifier: "com.apple.dock").first?.activate()
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                activate()
            }
        }
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

    /// Prevents the "ShowOnHover" feature.
    func preventShowOnHover() {
        isShowOnHoverPrevented = true
    }

    /// Allows the "ShowOnHover" feature.
    func allowShowOnHover() {
        isShowOnHoverPrevented = false
    }
}

// MARK: AppState: BindingExposable
extension AppState: BindingExposable { }

// MARK: - Logger
private extension Logger {
    /// The logger to use for the app state.
    static let appState = Logger(category: "AppState")
}
