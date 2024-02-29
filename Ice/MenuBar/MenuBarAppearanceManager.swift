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

    private let encoder: JSONEncoder

    private let decoder: JSONDecoder

    private let defaults: UserDefaults

    private(set) weak var menuBarManager: MenuBarManager?

    private(set) var appearancePanels = Set<MenuBarAppearancePanel>()

    private var cachedScreenCount = NSScreen.screens.count

    /// A Boolean value that indicates whether the appearance
    /// manager should retain any appearance panels.
    var shouldRetainAppearancePanels: Bool {
        configuration.hasShadow ||
        configuration.hasBorder ||
        configuration.shapeKind != .none ||
        configuration.tintKind != .none
    }

    /// A Boolean value that indicates whether an app is fullscreen.
    var isFullscreen: Bool {
        guard let windows = CGWindowListCopyWindowInfo(.optionOnScreenOnly, kCGNullWindowID) else {
            return false
        }
        for window in windows as NSArray {
            guard let info = window as? NSDictionary else {
                continue
            }
            if
                info[kCGWindowOwnerName] as? String == "Dock",
                info[kCGWindowName] as? String == "Fullscreen Backdrop"
            {
                return true
            }
        }
        return false
    }

    init(
        menuBarManager: MenuBarManager,
        encoder: JSONEncoder,
        decoder: JSONDecoder,
        defaults: UserDefaults
    ) {
        self.menuBarManager = menuBarManager
        self.encoder = encoder
        self.decoder = decoder
        self.defaults = defaults
    }

    func performSetup() {
        loadInitialState()
        configureCancellables()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [self] in
            // make sure all panels are ordered out before configuring
            // TODO: We may not need this...investigate.
            while let panel = appearancePanels.popFirst() {
                panel.orderOut(self)
            }
            configureAppearancePanels()
        }
    }

    /// Loads data from storage and sets the initial state
    /// of the manager from that data.
    private func loadInitialState() {
        do {
            configuration = try MenuBarAppearanceConfiguration(
                migratingFrom: defaults,
                encoder: encoder,
                decoder: decoder
            )
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
                while let panel = appearancePanels.popFirst() {
                    panel.orderOut(self)
                }
                configureAppearancePanels()
            }
            .store(in: &c)

        NSWorkspace.shared.notificationCenter
            .publisher(for: NSWorkspace.activeSpaceDidChangeNotification)
            .sink { [weak self] _ in
                guard let self else {
                    return
                }
                if
                    appearancePanels.isEmpty,
                    !isFullscreen
                {
                    configureAppearancePanels()
                } else {
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                        if self.isFullscreen {
                            while let panel = self.appearancePanels.popFirst() {
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
            } receiveValue: { [weak self] data in
                self?.defaults.set(data, forKey: Defaults.menuBarAppearanceConfiguration)
            }
            .store(in: &c)

        objectWillChange
            .sink { [weak self] in
                guard let self else {
                    return
                }
                // appearance panels may not have been configured yet;
                // since some of the properties on the manager might
                // call for them, try to configure now
                if appearancePanels.isEmpty {
                    configureAppearancePanels()
                }
            }
            .store(in: &c)

        cancellables = c
    }

    private func configureAppearancePanels() {
        guard shouldRetainAppearancePanels else {
            // remove all appearance panels if none of the properties
            // on the manager call for them
            appearancePanels.removeAll()
            return
        }

        var appearancePanels = Set<MenuBarAppearancePanel>()
        for screen in NSScreen.screens {
            let panel = MenuBarAppearancePanel(appearanceManager: self, owningScreen: screen)
            appearancePanels.insert(panel)
            // panel needs a reference to the menu bar frame, which is retrieved asynchronously; wait a bit before showing
            // FIXME: Show after the panel has the menu bar reference instead of waiting an arbitrary amount of time
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                panel.show()
            }
        }

        self.appearancePanels = appearancePanels
    }
}

// MARK: MenuBarAppearanceManager: BindingExposable
extension MenuBarAppearanceManager: BindingExposable { }

// MARK: - Logger
private extension Logger {
    static let appearanceManager = Logger(category: "MenuBarAppearanceManager")
}
