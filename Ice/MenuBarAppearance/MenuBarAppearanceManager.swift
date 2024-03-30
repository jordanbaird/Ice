//
//  MenuBarAppearanceManager.swift
//  Ice
//

import Combine
import OSLog
import ScreenCaptureKit
import SwiftUI

/// A type that manages the appearance of the menu bar.
final class MenuBarAppearanceManager: ObservableObject {
    /// The configuration that defines the appearance of the menu bar.
    @Published var configuration: MenuBarAppearanceConfiguration = .defaultConfiguration

    private var cancellables = Set<AnyCancellable>()

    private let encoder = JSONEncoder()

    private let decoder = JSONDecoder()

    private let defaults = UserDefaults.standard

    private(set) weak var menuBarManager: MenuBarManager?

    private(set) var overlayPanels = Set<MenuBarOverlayPanel>()

    private var cachedScreenCount = NSScreen.screens.count

    init(menuBarManager: MenuBarManager) {
        self.menuBarManager = menuBarManager
    }

    func performSetup() {
        loadInitialState()
        configureCancellables()
    }

    /// Loads data from storage and sets the initial state
    /// of the manager from that data.
    private func loadInitialState() {
        do {
            configuration = try .migrate(encoder: encoder, decoder: decoder)
        } catch {
            Logger.appearanceManager.error("Error decoding configuration: \(error)")
        }
    }

    private func configureCancellables() {
        var c = Set<AnyCancellable>()

        NotificationCenter.default
            .publisher(for: NSApplication.didChangeScreenParametersNotification)
            .sink { [weak self] _ in
                guard let self else {
                    return
                }
                let screenCount = NSScreen.screens.count
                guard cachedScreenCount != screenCount else {
                    return
                }
                defer {
                    cachedScreenCount = screenCount
                }
                while let panel = overlayPanels.popFirst() {
                    panel.orderOut(self)
                }
                configureOverlayPanels(with: configuration)
            }
            .store(in: &c)

        NSWorkspace.shared.notificationCenter
            .publisher(for: NSWorkspace.activeSpaceDidChangeNotification)
            .delay(for: 0.1, scheduler: DispatchQueue.main)
            .sink { [weak self] _ in
                guard
                    let self,
                    let menuBarManager,
                    let screen = NSScreen.main
                else {
                    return
                }
                if
                    overlayPanels.isEmpty,
                    !menuBarManager.isMenuBarHidden(for: screen)
                {
                    configureOverlayPanels(with: configuration)
                } else {
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                        if menuBarManager.isMenuBarHidden(for: screen) {
                            while let panel = self.overlayPanels.popFirst() {
                                panel.orderOut(self)
                            }
                        }
                    }
                }
            }
            .store(in: &c)

        $configuration
            .encode(encoder: encoder)
            .sink { completion in
                if case .failure(let error) = completion {
                    Logger.appearanceManager.error("Error encoding configuration: \(error)")
                }
            } receiveValue: { data in
                Defaults.set(data, forKey: .menuBarAppearanceConfiguration)
            }
            .store(in: &c)

        $configuration
            .sink { [weak self] configuration in
                guard let self else {
                    return
                }
                // overlay panels may not have been configured yet;
                // since some of the properties on the manager might
                // call for them, try to configure now
                if overlayPanels.isEmpty {
                    configureOverlayPanels(with: configuration)
                }
            }
            .store(in: &c)

        cancellables = c
    }

    /// Returns a Boolean value that indicates whether the
    /// manager should retain its overlay panels.
    private func shouldRetainOverlayPanels(for configuration: MenuBarAppearanceConfiguration) -> Bool {
        configuration.hasShadow ||
        configuration.hasBorder ||
        configuration.shapeKind != .none ||
        configuration.tintKind != .none
    }

    private func configureOverlayPanels(with configuration: MenuBarAppearanceConfiguration) {
        guard shouldRetainOverlayPanels(for: configuration) else {
            // remove all overlay panels if none of the properties
            // on the manager call for them
            overlayPanels.removeAll()
            return
        }

        var overlayPanels = Set<MenuBarOverlayPanel>()
        for screen in NSScreen.screens {
            let panel = MenuBarOverlayPanel(appearanceManager: self, owningScreen: screen)
            overlayPanels.insert(panel)
            // panel needs a reference to the menu bar frame, which is retrieved asynchronously; wait a bit before showing
            // FIXME: Show after the panel has the menu bar reference instead of waiting an arbitrary amount of time
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                panel.show()
            }
        }

        self.overlayPanels = overlayPanels
    }

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
    static let appearanceManager = Logger(category: "MenuBarAppearanceManager")
}
