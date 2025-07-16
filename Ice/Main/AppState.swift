//
//  AppState.swift
//  Ice
//

import Combine
import OSLog
import SwiftUI

/// The model for app-wide state.
@MainActor
final class AppState: ObservableObject {
    /// A Boolean value that indicates whether the active space is fullscreen.
    @Published private(set) var isActiveSpaceFullscreen = Bridging.isActiveSpaceFullscreen()

    /// A Boolean value that indicates whether the user is dragging a menu bar item.
    @Published private(set) var isDraggingMenuBarItem = false

    /// Model for the app's settings.
    let settings = AppSettings()

    /// Model for the app's permissions.
    let permissions = AppPermissions()

    /// Model for app-wide navigation.
    let navigationState = AppNavigationState()

    /// Manager for the state of the menu bar.
    let menuBarManager = MenuBarManager()

    /// Manager for the menu bar's appearance.
    let appearanceManager = MenuBarAppearanceManager()

    /// Manager for menu bar item spacing.
    let spacingManager = MenuBarItemSpacingManager()

    /// Manager for menu bar items.
    let itemManager = MenuBarItemManager()

    /// Global cache for menu bar item images.
    let imageCache = MenuBarItemImageCache()

    /// Manager for events received by the app.
    let eventManager = EventManager()

    /// Manager for app updates.
    let updatesManager = UpdatesManager()

    /// Manager for user notifications.
    let userNotificationManager = UserNotificationManager()

    /// Storage for internal observers.
    private var cancellables = Set<AnyCancellable>()

    /// Logger for the app state.
    private let logger = Logger(category: "AppState")

    /// Async setup actions, run once on first access.
    private lazy var setupTask = Task {
        permissions.stopAllChecks()

        if #available(macOS 26.0, *) {
            await MenuBarItemService.Connection.shared.start()
        }

        settings.performSetup(with: self)
        menuBarManager.performSetup(with: self)
        appearanceManager.performSetup(with: self)
        eventManager.performSetup(with: self)
        await itemManager.performSetup(with: self)
        imageCache.performSetup(with: self)
        updatesManager.performSetup(with: self)
        userNotificationManager.performSetup(with: self)

        configureCancellables()
    }

    /// Performs app state setup.
    ///
    /// - Parameter hasPermissions: If `true`, continues with setup normally.
    ///   If `false`, prompts the user to grant permissions.
    func performSetup(hasPermissions: Bool) {
        if hasPermissions {
            Task {
                logger.debug("Setting up app state")
                await setupTask.value
                logger.debug("Finished setting up app state")
            }
        } else {
            Task {
                // Delay to prevent conflicts with the app delegate.
                try? await Task.sleep(for: .milliseconds(100))
                activate(withPolicy: .regular)
                dismissWindow(.settings) // Shouldn't be open anyway.
                openWindow(.permissions)
            }
        }
    }

    /// Configures the internal observers for the app state.
    private func configureCancellables() {
        var c = Set<AnyCancellable>()

        Publishers.Merge3(
            NSWorkspace.shared.notificationCenter
                .publisher(for: NSWorkspace.activeSpaceDidChangeNotification)
                .replace(with: ()),
            // Frontmost application change can indicate a space change from one display to
            // another, which gets ignored by NSWorkspace.activeSpaceDidChangeNotification.
            NSWorkspace.shared
                .publisher(for: \.frontmostApplication)
                .replace(with: ()),
            // Clicking into a fullscreen space from another space is also ignored.
            UniversalEventMonitor
                .publisher(for: .leftMouseDown)
                .delay(for: 0.1, scheduler: DispatchQueue.main)
                .replace(with: ())
        )
        .receive(on: DispatchQueue.main)
        .replace {
            Bridging.isActiveSpaceFullscreen()
        }
        .removeDuplicates()
        .sink { [weak self] isFullscreen in
            self?.isActiveSpaceFullscreen = isFullscreen
        }
        .store(in: &c)

        NSWorkspace.shared.publisher(for: \.frontmostApplication)
            .receive(on: DispatchQueue.main)
            .map { $0 == .current }
            .removeDuplicates()
            .sink { [weak self] isFrontmost in
                self?.navigationState.isAppFrontmost = isFrontmost
            }
            .store(in: &c)

        publisherForWindow(.settings)
            .flatMap { $0.publisher } // Short circuit if nil.
            .flatMap { $0.publisher(for: \.isVisible) }
            .throttle(for: 0.1, scheduler: DispatchQueue.main, latest: true)
            .removeDuplicates()
            .sink { [weak self] isPresented in
                self?.navigationState.isSettingsPresented = isPresented
            }
            .store(in: &c)

        eventManager.$isDraggingMenuBarItem
            .removeDuplicates()
            .sink { [weak self] isDragging in
                self?.isDraggingMenuBarItem = isDragging
            }
            .store(in: &c)

        Publishers.CombineLatest(
            navigationState.$isAppFrontmost,
            navigationState.$isSettingsPresented
        )
        .map { $0 && $1 }
        .throttle(for: 0.1, scheduler: DispatchQueue.main, latest: true)
        .merge(with: Just(true).delay(for: 1, scheduler: DispatchQueue.main))
        .sink { [weak self] shouldUpdate in
            guard let self, shouldUpdate else {
                return
            }
            Task {
                await self.imageCache.updateCacheWithoutChecks(sections: MenuBarSection.Name.allCases)
            }
        }
        .store(in: &c)

        menuBarManager.objectWillChange
            .sink { [weak self] in
                self?.objectWillChange.send()
            }
            .store(in: &c)
        permissions.objectWillChange
            .sink { [weak self] in
                self?.objectWillChange.send()
            }
            .store(in: &c)
        settings.objectWillChange
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

    func hasPermission(_ key: AppPermissions.PermissionKey) -> Bool {
        switch key {
        case .accessibility:
            permissions.accessibility.hasPermission
        case .screenRecording:
            permissions.screenRecording.hasPermission
        }
    }

    /// Returns a publisher for the window with the given identifier.
    func publisherForWindow(_ id: IceWindowIdentifier) -> some Publisher<NSWindow?, Never> {
        NSApp.publisher(for: \.windows).mergeMap { window in
            window.publisher(for: \.identifier)
                .map { [weak window] identifier in
                    guard identifier?.rawValue == id.rawValue else {
                        return nil
                    }
                    return window
                }
                .first { $0 != nil }
                .replaceEmpty(with: nil)
        }
    }

    /// Opens the window with the given identifier.
    func openWindow(_ id: IceWindowIdentifier) {
        // Defer to the next run loop to prevent conflicts with SwiftUI.
        DispatchQueue.main.async {
            self.logger.debug("Opening window with id: \(id, privacy: .public)")
            EnvironmentValues().openWindow(id: id)
        }
    }

    /// Dismisses the window with the given identifier.
    func dismissWindow(_ id: IceWindowIdentifier) {
        // Defer to the next run loop to prevent conflicts with SwiftUI.
        DispatchQueue.main.async {
            self.logger.debug("Dismissing window with id: \(id, privacy: .public)")
            EnvironmentValues().dismissWindow(id: id)
        }
    }

    /// Activates the app and sets its activation policy.
    func activate(withPolicy policy: NSApplication.ActivationPolicy) {

        // What follows is NOT at all straightforward, but it seems to
        // make app activation (mostly) reliable after changes made in
        // macOS 14.

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

    /// Deactivates the app and sets its activation policy.
    func deactivate(withPolicy policy: NSApplication.ActivationPolicy) {
        NSApp.deactivate()
        NSApp.setActivationPolicy(policy)
    }
}

// MARK: AppState: BindingExposable
extension AppState: BindingExposable { }
