//
//  MenuBarAppearanceManager.swift
//  Ice
//

import Cocoa
import Combine
import OSLog

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

    /// The amount to inset the menu bar if called for by the configuration.
    let menuBarInsetAmount: CGFloat = if #available(macOS 26.0, *) { 3.5 } else { 5 }

    /// Performs initial setup of the manager.
    func performSetup(with appState: AppState) {
        self.appState = appState
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
            Logger.serialization.error("Error decoding menu bar appearance configuration: \(error)")
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
                // Rebuild the panels for the new screens. This also closes the
                // existing panels, which would otherwise keep their update loops
                // running while ordered out.
                configureOverlayPanels(with: configuration)
            }
            .store(in: &c)

        // Debounce saving, as the configuration changes continuously while
        // the user drags a slider or color picker.
        $configuration
            .debounce(for: 0.3, scheduler: DispatchQueue.main)
            .sink { [weak self] configuration in
                self?.saveConfiguration(configuration)
            }
            .store(in: &c)

        // Save the latest configuration in case the app terminates before
        // the debounce interval elapses.
        NotificationCenter.default
            .publisher(for: NSApplication.willTerminateNotification)
            .sink { [weak self] _ in
                guard let self else {
                    return
                }
                saveConfiguration(configuration)
            }
            .store(in: &c)

        $configuration
            .throttle(for: 0.1, scheduler: DispatchQueue.main, latest: true)
            .sink { [weak self] configuration in
                guard let self else {
                    return
                }
                // The overlay panels may not have been configured yet. Since some of the
                // properties on the manager might call for them, try to configure now.
                // If they are no longer called for, close them, so they stop their
                // timers, monitors, and wallpaper captures.
                if overlayPanels.isEmpty == needsOverlayPanels(for: configuration) {
                    configureOverlayPanels(with: configuration)
                }
            }
            .store(in: &c)

        cancellables = c
    }

    /// Encodes the given configuration and saves it to UserDefaults.
    private func saveConfiguration(_ configuration: MenuBarAppearanceConfigurationV2) {
        do {
            let data = try encoder.encode(configuration)
            Defaults.set(data, forKey: .menuBarAppearanceConfigurationV2)
        } catch {
            Logger.serialization.error("Error encoding menu bar appearance configuration: \(error)")
        }
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
        if configuration.shapeKind != .noShape {
            return true
        }
        if current.tintKind != .noTint {
            return true
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

        // Close the panels being replaced before building their successors.
        //
        // A visible NSWindow is retained by AppKit, so dropping the last Swift
        // reference to it does not close it. Reassigning `overlayPanels` therefore
        // left the previous set alive and on screen, each panel still running its
        // own update loops. This function runs on every screen-parameter change,
        // so attaching and detaching a display accumulated a full set of live
        // panels per display each time, all competing to own the menu bar's
        // appearance. The not-needed path above already closes them; this one did
        // not.
        while let panel = overlayPanels.popFirst() {
            panel.close()
        }

        var overlayPanels = Set<MenuBarOverlayPanel>()
        for screen in NSScreen.screens {
            let panel = MenuBarOverlayPanel(appState: appState, owningScreen: screen)
            overlayPanels.insert(panel)
            panel.needsShow = true
        }

        self.overlayPanels = overlayPanels
    }
}
