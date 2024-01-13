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
    /// A Boolean value that indicates whether the menu bar
    /// should have a shadow.
    @Published var hasShadow: Bool = false

    /// A Boolean value that indicates whether the menu bar
    /// should have a border.
    @Published var hasBorder: Bool = false

    /// The color of the menu bar's border.
    @Published var borderColor: CGColor = .black

    /// The width of the menu bar's border.
    @Published var borderWidth: Double = 1

    /// The shape of the menu bar.
    @Published var shapeKind: MenuBarShapeKind = .none

    /// Information for the menu bar's shape when it is in
    /// the ``MenuBarShapeKind/full`` state.
    @Published var fullShapeInfo: MenuBarFullShapeInfo = .default

    /// Information for the menu bar's shape when it is in
    /// the ``MenuBarShapeKind/split`` state.
    @Published var splitShapeInfo: MenuBarSplitShapeInfo = .default

    /// The tint kind currently in use.
    @Published var tintKind: MenuBarTintKind = .none

    /// The user's currently chosen tint color.
    @Published var tintColor: CGColor = .black

    /// The user's currently chosen tint gradient.
    @Published var tintGradient: CustomGradient = .defaultMenuBarTint

    /// The current desktop wallpaper, clipped to the bounds
    /// of the menu bar.
    @Published var desktopWallpaper: CGImage?

    /// A Boolean value that indicates whether the screen
    /// is currently locked.
    @Published private(set) var screenIsLocked = false

    /// A Boolean value that indicates whether the screen
    /// saver is currently active.
    @Published private(set) var screenSaverIsActive = false

    private var cancellables = Set<AnyCancellable>()

    private(set) weak var menuBar: MenuBar?

    private lazy var backingPanel = MenuBarBackingPanel(appearanceManager: self)
    private lazy var overlayPanel = MenuBarOverlayPanel(appearanceManager: self)

    init(menuBar: MenuBar) {
        self.menuBar = menuBar
    }

    func performSetup() {
        loadInitialState()
        configureCancellables()
        Task.detached { @MainActor [self] in
            try await Task.sleep(for: .milliseconds(500))
            backingPanel.configureCancellables()
            overlayPanel.configureCancellables()
        }
    }

    /// Loads data from storage and sets the initial state
    /// of the manager from that data.
    private func loadInitialState() {
        let defaults = UserDefaults.standard
        let decoder = JSONDecoder()

        hasShadow = defaults.bool(forKey: Defaults.menuBarHasShadow)
        hasBorder = defaults.bool(forKey: Defaults.menuBarHasBorder)
        borderWidth = defaults.object(forKey: Defaults.menuBarBorderWidth) as? Double ?? 1
        tintKind = MenuBarTintKind(rawValue: defaults.integer(forKey: Defaults.menuBarTintKind)) ?? .none

        do {
            if let borderColorData = defaults.data(forKey: Defaults.menuBarBorderColor) {
                borderColor = try decoder.decode(CodableColor.self, from: borderColorData).cgColor
            }
            if let tintColorData = defaults.data(forKey: Defaults.menuBarTintColor) {
                tintColor = try decoder.decode(CodableColor.self, from: tintColorData).cgColor
            }
            if let tintGradientData = defaults.data(forKey: Defaults.menuBarTintGradient) {
                tintGradient = try decoder.decode(CustomGradient.self, from: tintGradientData)
            }
            if let shapeKindData = defaults.data(forKey: Defaults.menuBarShapeKind) {
                shapeKind = try decoder.decode(MenuBarShapeKind.self, from: shapeKindData)
            }
            if let fullShapeData = defaults.data(forKey: Defaults.menuBarFullShapeInfo) {
                fullShapeInfo = try decoder.decode(MenuBarFullShapeInfo.self, from: fullShapeData)
            }
            if let splitShapeData = defaults.data(forKey: Defaults.menuBarSplitShapeInfo) {
                splitShapeInfo = try decoder.decode(MenuBarSplitShapeInfo.self, from: splitShapeData)
            }
        } catch {
            Logger.appearanceManager.error("Error decoding value: \(error)")
        }
    }

    private func configureCancellables() {
        var c = Set<AnyCancellable>()

        let defaults = UserDefaults.standard
        let encoder = JSONEncoder()

        DistributedNotificationCenter.default()
            .publisher(for: Notification.Name("com.apple.screenIsLocked"))
            .sink { [weak self] _ in
                self?.screenIsLocked = true
            }
            .store(in: &c)

        DistributedNotificationCenter.default()
            .publisher(for: Notification.Name("com.apple.screenIsUnlocked"))
            .sink { [weak self] _ in
                self?.screenIsLocked = false
            }
            .store(in: &c)

        DistributedNotificationCenter.default()
            .publisher(for: Notification.Name("com.apple.screensaver.didstart"))
            .sink { [weak self] _ in
                self?.screenSaverIsActive = true
            }
            .store(in: &c)

        DistributedNotificationCenter.default()
            .publisher(for: Notification.Name("com.apple.screensaver.didstop"))
            .sink { [weak self] _ in
                self?.screenSaverIsActive = false
            }
            .store(in: &c)

        NSWorkspace.shared.notificationCenter
            .publisher(for: NSWorkspace.activeSpaceDidChangeNotification)
            .sink { [weak self] _ in
                self?.updateDesktopWallpaper()
            }
            .store(in: &c)

        Timer.publish(every: 3, on: .main, in: .common)
            .autoconnect()
            .sink { [weak self] _ in
                self?.updateDesktopWallpaper()
            }
            .store(in: &c)

        $hasShadow
            .receive(on: DispatchQueue.main)
            .sink { hasShadow in
                defaults.set(hasShadow, forKey: Defaults.menuBarHasShadow)
            }
            .store(in: &c)

        $hasBorder
            .receive(on: DispatchQueue.main)
            .sink { hasBorder in
                defaults.set(hasBorder, forKey: Defaults.menuBarHasBorder)
            }
            .store(in: &c)

        $borderColor
            .receive(on: DispatchQueue.main)
            .sink { borderColor in
                do {
                    let data = try encoder.encode(CodableColor(cgColor: borderColor))
                    defaults.set(data, forKey: Defaults.menuBarBorderColor)
                } catch {
                    Logger.appearanceManager.error("Error encoding border color: \(error)")
                }
            }
            .store(in: &c)

        $borderWidth
            .receive(on: DispatchQueue.main)
            .sink { borderWidth in
                defaults.set(borderWidth, forKey: Defaults.menuBarBorderWidth)
            }
            .store(in: &c)

        $tintKind
            .receive(on: DispatchQueue.main)
            .sink { tintKind in
                defaults.set(tintKind.rawValue, forKey: Defaults.menuBarTintKind)
            }
            .store(in: &c)

        $tintColor
            .receive(on: DispatchQueue.main)
            .sink { tintColor in
                do {
                    let data = try encoder.encode(CodableColor(cgColor: tintColor))
                    defaults.set(data, forKey: Defaults.menuBarTintColor)
                } catch {
                    Logger.appearanceManager.error("Error encoding tint color: \(error)")
                }
            }
            .store(in: &c)

        $tintGradient
            .receive(on: DispatchQueue.main)
            .encode(encoder: encoder)
            .sink { completion in
                if case .failure(let error) = completion {
                    Logger.appearanceManager.error("Error encoding tint gradient: \(error)")
                }
            } receiveValue: { data in
                defaults.set(data, forKey: Defaults.menuBarTintGradient)
            }
            .store(in: &c)

        $shapeKind
            .receive(on: DispatchQueue.main)
            .encode(encoder: encoder)
            .sink { completion in
                if case .failure(let error) = completion {
                    Logger.appearanceManager.error("Error encoding menu bar shape kind: \(error)")
                }
            } receiveValue: { [weak self] data in
                self?.updateDesktopWallpaper()
                defaults.set(data, forKey: Defaults.menuBarShapeKind)
            }
            .store(in: &c)

        $fullShapeInfo
            .receive(on: DispatchQueue.main)
            .encode(encoder: encoder)
            .sink { completion in
                if case .failure(let error) = completion {
                    Logger.appearanceManager.error("Error encoding menu bar full shape info: \(error)")
                }
            } receiveValue: { data in
                defaults.set(data, forKey: Defaults.menuBarFullShapeInfo)
            }
            .store(in: &c)

        $splitShapeInfo
            .receive(on: DispatchQueue.main)
            .encode(encoder: encoder)
            .sink { completion in
                if case .failure(let error) = completion {
                    Logger.appearanceManager.error("Error encoding menu bar split shape info: \(error)")
                }
            } receiveValue: { data in
                defaults.set(data, forKey: Defaults.menuBarSplitShapeInfo)
            }
            .store(in: &c)

        cancellables = c
    }

    private func updateDesktopWallpaper() {
        guard shapeKind != .none else {
            desktopWallpaper = nil
            return
        }

        guard !screenIsLocked else {
            Logger.appearanceManager.debug("Screen is locked")
            return
        }

        guard !screenSaverIsActive else {
            Logger.appearanceManager.debug("Screen saver is active")
            return
        }

        guard
            let appState = menuBar?.appState,
            appState.permissionsManager.screenRecordingPermission.hasPermission
        else {
            Logger.appearanceManager.notice("Missing screen capture permissions")
            return
        }

        Task { @MainActor in
            do {
                let content = try await SCShareableContent.current

                let wallpaperWindowPredicate: (SCWindow) -> Bool = { window in
                    // wallpaper window belongs to the Dock process
                    window.owningApplication?.bundleIdentifier == "com.apple.dock" &&
                    window.isOnScreen &&
                    window.title?.hasPrefix("Wallpaper-") == true
                }
                let menuBarWindowPredicate: (SCWindow) -> Bool = { window in
                    // menu bar window belongs to the WindowServer process
                    // (identified by an empty string)
                    window.owningApplication?.bundleIdentifier == "" &&
                    window.windowLayer == kCGMainMenuWindowLevel &&
                    window.title == "Menubar"
                }

                guard
                    let wallpaperWindow = content.windows.first(where: wallpaperWindowPredicate),
                    let menuBarWindow = content.windows.first(where: menuBarWindowPredicate)
                else {
                    return
                }

                let image = try await ScreenshotManager.captureImage(
                    withTimeout: .milliseconds(500),
                    window: wallpaperWindow,
                    captureRect: menuBarWindow.frame,
                    options: .ignoreFraming
                )

                if desktopWallpaper?.dataProvider?.data != image.dataProvider?.data {
                    desktopWallpaper = image
                }
            } catch {
                Logger.appearanceManager.error("Error updating desktop wallpaper: \(error)")
            }
        }
    }
}

// MARK: MenuBarAppearanceManager: BindingExposable
extension MenuBarAppearanceManager: BindingExposable { }

// MARK: - Logger
private extension Logger {
    static let appearanceManager = Logger(category: "MenuBarAppearanceManager")
}
