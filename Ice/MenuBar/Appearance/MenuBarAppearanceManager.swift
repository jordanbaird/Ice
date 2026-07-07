//
//  MenuBarAppearanceManager.swift
//  Ice
//

import Cocoa
import Combine

/// A manager for the appearance of the menu bar.
@MainActor
final class MenuBarAppearanceManager: ObservableObject {
    /// The current menu bar appearance configuration.
    @Published var configuration: MenuBarAppearanceConfigurationV2 = .defaultConfiguration

    /// The currently previewed partial configuration.
    @Published var previewConfiguration: MenuBarAppearancePartialConfiguration?

    /// The shared app state.
    private weak var appState: AppState?

    /// Encoder for UserDefaults values.
    private let encoder = JSONEncoder()

    /// Decoder for UserDefaults values.
    private let decoder = JSONDecoder()

    /// Storage for internal observers.
    private var cancellables = Set<AnyCancellable>()

    /// The currently managed menu bar overlay panels.
    private(set) var overlayPanels = Set<MenuBarOverlayPanel>()

    /// The currently managed screen bottom corner overlay panels.
    private(set) var bottomCornerOverlayPanels = Set<ScreenBottomCornerOverlayPanel>()

    /// The amount to inset the menu bar if called for by the configuration.
    let menuBarInsetAmount: CGFloat = 5

    /// Creates a manager with the given app state.
    init(appState: AppState) {
        self.appState = appState
    }

    /// Performs initial setup of the manager.
    func performSetup() {
        loadInitialState()
        configureCancellables()
    }

    /// Loads the initial values for the configuration.
    private func loadInitialState() {
        do {
            if let data = Defaults.data(forKey: .menuBarAppearanceConfigurationV2) {
                configuration = try decoder.decode(MenuBarAppearanceConfigurationV2.self, from: data)
            }
        } catch {
            Logger.appearanceManager.error("Error decoding configuration: \(error)")
        }
    }

    /// Configures the internal observers for the manager.
    private func configureCancellables() {
        var c = Set<AnyCancellable>()

        NotificationCenter.default
            .publisher(for: NSApplication.didChangeScreenParametersNotification)
            .debounce(for: 0.1, scheduler: DispatchQueue.main)
            .sink { [weak self] _ in
                guard let self else {
                    return
                }
                while let panel = overlayPanels.popFirst() {
                    panel.close()
                }
                while let panel = bottomCornerOverlayPanels.popFirst() {
                    panel.close()
                }
                configureOverlayPanels(with: configuration)
                configureBottomCornerOverlayPanels(with: configuration)
            }
            .store(in: &c)

        NSWorkspace.shared.notificationCenter
            .publisher(for: NSWorkspace.activeSpaceDidChangeNotification)
            .debounce(for: 0.1, scheduler: DispatchQueue.main)
            .sink { [weak self] _ in
                guard let self else {
                    return
                }
                if needsOverlayPanels(for: configuration) {
                    configureOverlayPanels(with: configuration)
                    for panel in overlayPanels {
                        panel.needsShow = true
                    }
                }
                for panel in bottomCornerOverlayPanels {
                    panel.updateVisibility()
                }
            }
            .store(in: &c)

        // Dynamic appearance flips `current.appearanceKind` without mutating
        // the configuration value itself. Trigger a re-show so panels that
        // depend on the current appearance (rounded top corners) reframe.
        DistributedNotificationCenter.default()
            .publisher(for: DistributedNotificationCenter.interfaceThemeChangedNotification)
            .debounce(for: 0.15, scheduler: DispatchQueue.main)
            .sink { [weak self] _ in
                guard let self else {
                    return
                }
                for panel in overlayPanels {
                    panel.needsShow = true
                }
            }
            .store(in: &c)

        $configuration
            .encode(encoder: encoder)
            .receive(on: DispatchQueue.main)
            .sink { completion in
                if case .failure(let error) = completion {
                    Logger.appearanceManager.error("Error encoding configuration: \(error)")
                }
            } receiveValue: { data in
                Defaults.set(data, forKey: .menuBarAppearanceConfigurationV2)
            }
            .store(in: &c)

        $configuration
            .throttle(for: 0.1, scheduler: DispatchQueue.main, latest: true)
            .sink { [weak self] configuration in
                guard let self else {
                    return
                }
                let needsMenuBar = needsOverlayPanels(for: configuration)
                let hasMenuBar = !overlayPanels.isEmpty
                if needsMenuBar && !hasMenuBar {
                    configureOverlayPanels(with: configuration)
                } else if needsMenuBar && hasMenuBar {
                    configureOverlayPanels(with: configuration)
                    // Settings that affect panel frame (e.g. rounded top corners) need a re-show.
                    for panel in overlayPanels {
                        panel.needsShow = true
                    }
                } else if !needsMenuBar && hasMenuBar {
                    while let panel = overlayPanels.popFirst() {
                        panel.close()
                    }
                }
                configureBottomCornerOverlayPanels(with: configuration)
            }
            .store(in: &c)

        if let appState {
            appState.$isActiveSpaceFullscreen
                .receive(on: DispatchQueue.main)
                .sink { [weak self] _ in
                    guard let self else {
                        return
                    }
                    for panel in bottomCornerOverlayPanels {
                        panel.updateVisibility()
                    }
                }
                .store(in: &c)
        }

        cancellables = c
    }

    /// Returns a Boolean value that indicates whether a set of overlay panels
    /// is needed for the given configuration.
    private func needsOverlayPanels(for configuration: MenuBarAppearanceConfigurationV2) -> Bool {
        let current = configuration.current
        if current.hasShadow {
            return true
        }
        if current.hasBorder {
            return true
        }
        if configuration.shapeKind != .none {
            return true
        }
        if current.appearanceKind != .none {
            return true
        }
        for screen in NSScreen.screens {
            if hasActiveRoundedTopScreenCorners(for: screen, in: configuration) {
                return true
            }
        }
        return false
    }

    /// Returns whether the configuration's effective settings for the given
    /// screen meet all of the gating conditions required to render rounded
    /// top screen corners.
    func hasActiveRoundedTopScreenCorners(for screen: NSScreen, in configuration: MenuBarAppearanceConfigurationV2) -> Bool {
        let info = configuration.effectiveScreenShapeInfo(for: screen)
        return info.hasRoundedTopCorners
            && configuration.shapeKind == .none
            && configuration.current.appearanceKind != .none
    }

    /// Returns a Boolean value that indicates whether a set of screen bottom
    /// corner overlay panels is needed for the given configuration.
    private func needsBottomCornerOverlayPanels(for configuration: MenuBarAppearanceConfigurationV2) -> Bool {
        for screen in NSScreen.screens {
            if configuration.effectiveScreenShapeInfo(for: screen).hasRoundedBottomCorners {
                return true
            }
        }
        return false
    }

    /// Configures the manager's overlay panels, if required by the given configuration.
    private func configureOverlayPanels(with configuration: MenuBarAppearanceConfigurationV2) {
        guard
            let appState,
            needsOverlayPanels(for: configuration)
        else {
            while let panel = overlayPanels.popFirst() {
                panel.close()
            }
            return
        }

        let existingScreens = Set(overlayPanels.map { $0.owningScreen })
        if existingScreens == Set(NSScreen.screens), overlayPanels.count == NSScreen.screens.count {
            return
        }

        while let panel = overlayPanels.popFirst() {
            panel.close()
        }

        var panels = Set<MenuBarOverlayPanel>()
        for screen in NSScreen.screens {
            let panel = MenuBarOverlayPanel(
                appState: appState,
                owningScreen: screen
            )
            panel.needsShow = true
            panels.insert(panel)
        }
        overlayPanels = panels
    }

    /// Configures the manager's screen bottom corner overlay panels, if
    /// required by the given configuration.
    private func configureBottomCornerOverlayPanels(with configuration: MenuBarAppearanceConfigurationV2) {
        guard
            let appState,
            needsBottomCornerOverlayPanels(for: configuration)
        else {
            while let panel = bottomCornerOverlayPanels.popFirst() {
                panel.close()
            }
            return
        }

        let existingScreens = Set(bottomCornerOverlayPanels.map { $0.owningScreen })
        if existingScreens == Set(NSScreen.screens) {
            for panel in bottomCornerOverlayPanels {
                panel.show()
            }
            return
        }

        while let panel = bottomCornerOverlayPanels.popFirst() {
            panel.close()
        }

        var panels = Set<ScreenBottomCornerOverlayPanel>()
        for screen in NSScreen.screens {
            let panel = ScreenBottomCornerOverlayPanel(appState: appState, owningScreen: screen)
            panels.insert(panel)
            panel.show()
        }
        self.bottomCornerOverlayPanels = panels
    }

    /// Sets the value of ``MenuBarOverlayPanel/isDraggingMenuBarItem`` for each
    /// of the manager's overlay panels.
    func setIsDraggingMenuBarItem(_ isDragging: Bool) {
        for panel in overlayPanels {
            panel.isDraggingMenuBarItem = isDragging
        }
    }
}

// MARK: MenuBarAppearanceManager: BindingExposable
extension MenuBarAppearanceManager: BindingExposable { }

// MARK: - Logger
private extension Logger {
    /// The logger to use for the menu bar appearance manager.
    static let appearanceManager = Logger(category: "MenuBarAppearanceManager")
}
