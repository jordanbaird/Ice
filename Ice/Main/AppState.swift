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
    /// Information for the active space.
    @Published private(set) var activeSpace = SpaceInfo.activeSpace()

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

    /// Manager for input events received by the app.
    let hidEventManager = HIDEventManager()

    /// Manager for app updates.
    let updatesManager = UpdatesManager()

    /// Manager for user notifications.
    let userNotificationManager = UserNotificationManager()

    /// Storage for ``concealer27``, typed loosely so the property exists on every macOS.
    private var concealer27Storage: AnyObject?

    /// Hides menu bar items on macOS 27.
    @available(macOS 27.0, *)
    var concealer27: Concealer27 {
        if let concealer = concealer27Storage as? Concealer27 {
            return concealer
        }
        let concealer = Concealer27()
        concealer27Storage = concealer
        return concealer
    }

    /// Storage for ``itemImageStore27``, typed loosely so the property exists on every macOS.
    private var itemImageStore27Storage: AnyObject?

    /// Images of menu bar items on macOS 27.
    @available(macOS 27.0, *)
    var itemImageStore27: ItemImageStore27 {
        if let store = itemImageStore27Storage as? ItemImageStore27 {
            return store
        }
        let store = ItemImageStore27()
        itemImageStore27Storage = store
        return store
    }

    /// Storage for internal observers.
    private var cancellables = Set<AnyCancellable>()

    /// Logger for the app state.
    private let logger = Logger(category: "AppState")

    /// Async setup actions, run once on first access.
    private lazy var setupTask = Task {
        permissions.stopAllChecks()

        settings.performSetup(with: self)
        menuBarManager.performSetup(with: self)

        if #available(macOS 27.0, *) {
            // macOS 27 has no item windows: bounds come from Accessibility, and the
            // owning process is known directly, without the item service.
            Bridging.syntheticWindowBoundsProvider = MenuBarItemProvider27.currentBounds(for:)
        } else if #available(macOS 26.0, *) {
            await MenuBarItemService.Connection.shared.start()
        }

        appearanceManager.performSetup(with: self)
        hidEventManager.performSetup(with: self)
        if #available(macOS 27.0, *) {
            // Hiding does not need the item cache, and the first read of the items can
            // take seconds (measured 9 s), so it starts before the item manager's setup.
            concealer27.performSetup(with: self)
        }
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

        // Listen for changes to the active space. We need handle some special
        // cases that NSWorkspace.shared.notificationCenter seems to miss.
        //
        // Special cases:
        //
        // * Changes to the frontmost application -- may indicate that a space
        //   on another display was made active.
        // * Left mouse down -- user may have clicked into a fullscreen space.
        //   To account for variations in system timing, we publish a value
        //   immediately upon receipt of the event, then publish another value
        //   after a delay.
        NSWorkspace.shared.notificationCenter
            .publisher(for: NSWorkspace.activeSpaceDidChangeNotification)
            .discardMerge(NSWorkspace.shared.publisher(for: \.frontmostApplication))
            .discardMerge(EventMonitor.publish(events: .leftMouseDown, scope: .universal).flatMap { _ in
                let initial = Just(())
                let delayed = initial.delay(for: 0.1, scheduler: DispatchQueue.main)
                return Publishers.Merge(initial, delayed)
            })
            .replace { Bridging.getActiveSpaceID() }
            .removeDuplicates()
            .sink { [weak self] spaceID in
                self?.activeSpace = SpaceInfo(spaceID: spaceID)
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
            .map { window -> AnyPublisher<Bool, Never> in
                guard let window else {
                    return Just(false).eraseToAnyPublisher()
                }
                return window.publisher(for: \.isVisible).eraseToAnyPublisher()
            }
            .switchToLatest()
            .throttle(for: 0.1, scheduler: DispatchQueue.main, latest: true)
            .removeDuplicates()
            .sink { [weak self] isPresented in
                self?.navigationState.isSettingsPresented = isPresented
            }
            .store(in: &c)

        hidEventManager.$isDraggingMenuBarItem
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

    /// Returns a Boolean value indicating whether the app has been
    /// granted the permission associated with the given key.
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
        // SwiftUI can assign the identifier after adding the window to
        // the app, so observe the identifiers of the current windows too.
        // Switching to the latest set cancels the observers of the old one.
        NSApp.publisher(for: \.windows)
            .map { windows in
                Publishers.MergeMany(windows.map { $0.publisher(for: \.identifier, options: []) })
                    .replace(with: ())
                    .prepend(())
                    .map {
                        windows.first { $0.identifier?.rawValue == id.rawValue }
                    }
            }
            .switchToLatest()
            .removeDuplicates { $0 === $1 }
    }

    /// Opens the window with the given identifier.
    func openWindow(_ id: IceWindowIdentifier) {
        // Async prevents conflicts with SwiftUI.
        DispatchQueue.main.async {
            self.logger.debug("Opening window with id: \(id, privacy: .public)")
            EnvironmentValues().openWindow(id: id)
        }
    }

    /// Dismisses the window with the given identifier.
    func dismissWindow(_ id: IceWindowIdentifier) {
        // Async prevents conflicts with SwiftUI.
        DispatchQueue.main.async {
            self.logger.debug("Dismissing window with id: \(id, privacy: .public)")
            EnvironmentValues().dismissWindow(id: id)
        }
    }

    /// Activates the app and sets its activation policy.
    func activate(withPolicy policy: NSApplication.ActivationPolicy? = nil) {
        if let policy {
            NSApp.setActivationPolicy(policy)
        }
        // NSApplication.activate(ignoringOtherApps:) is deprecated, with
        // no suitable alternative for explicit activation, so we activate
        // through NSRunningApplication.current for now.
        guard let frontmost = NSWorkspace.shared.frontmostApplication else {
            NSRunningApplication.current.activate()
            return
        }
        NSRunningApplication.current.activate(from: frontmost)
    }

    /// Deactivates the app and sets its activation policy.
    func deactivate(withPolicy policy: NSApplication.ActivationPolicy? = nil) {
        if let policy {
            NSApp.setActivationPolicy(policy)
        }
        NSApp.deactivate()
    }
}
