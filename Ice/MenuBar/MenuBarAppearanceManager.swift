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

    /// A Boolean value that indicates whether the appearance
    /// manager should retain any appearance panels.
    var shouldRetainAppearancePanels: Bool {
        hasShadow ||
        hasBorder ||
        shapeKind != .none ||
        tintKind != .none
    }

    private var cancellables = Set<AnyCancellable>()

    private let encoder: JSONEncoder

    private let decoder: JSONDecoder

    private let defaults: UserDefaults

    private(set) weak var menuBarManager: MenuBarManager?

    private(set) var appearancePanels = Set<MenuBarAppearancePanel>()

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

        NotificationCenter.default
            .publisher(for: NSApplication.didChangeScreenParametersNotification)
            .sink { [weak self] _ in
                guard let self else {
                    return
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

        $hasShadow
            .sink { [weak self] hasShadow in
                self?.defaults.set(hasShadow, forKey: Defaults.menuBarHasShadow)
            }
            .store(in: &c)

        $hasBorder
            .sink { [weak self] hasBorder in
                self?.defaults.set(hasBorder, forKey: Defaults.menuBarHasBorder)
            }
            .store(in: &c)

        $borderColor
            .map(\.codable)
            .encode(encoder: encoder)
            .sink { completion in
                if case .failure(let error) = completion {
                    Logger.appearanceManager.error("Error encoding border color: \(error)")
                }
            } receiveValue: { [weak self] data in
                self?.defaults.set(data, forKey: Defaults.menuBarBorderColor)
            }
            .store(in: &c)

        $borderWidth
            .sink { [weak self] borderWidth in
                self?.defaults.set(borderWidth, forKey: Defaults.menuBarBorderWidth)
            }
            .store(in: &c)

        $tintKind
            .sink { [weak self] tintKind in
                self?.defaults.set(tintKind.rawValue, forKey: Defaults.menuBarTintKind)
            }
            .store(in: &c)

        $tintColor
            .map(\.codable)
            .encode(encoder: encoder)
            .sink { completion in
                if case .failure(let error) = completion {
                    Logger.appearanceManager.error("Error encoding tint color: \(error)")
                }
            } receiveValue: { [weak self] data in
                self?.defaults.set(data, forKey: Defaults.menuBarTintColor)
            }
            .store(in: &c)

        $tintGradient
            .encode(encoder: encoder)
            .sink { completion in
                if case .failure(let error) = completion {
                    Logger.appearanceManager.error("Error encoding tint gradient: \(error)")
                }
            } receiveValue: { [weak self] data in
                self?.defaults.set(data, forKey: Defaults.menuBarTintGradient)
            }
            .store(in: &c)

        $shapeKind
            .encode(encoder: encoder)
            .sink { completion in
                if case .failure(let error) = completion {
                    Logger.appearanceManager.error("Error encoding menu bar shape kind: \(error)")
                }
            } receiveValue: { [weak self] data in
                self?.defaults.set(data, forKey: Defaults.menuBarShapeKind)
            }
            .store(in: &c)

        $fullShapeInfo
            .encode(encoder: encoder)
            .sink { completion in
                if case .failure(let error) = completion {
                    Logger.appearanceManager.error("Error encoding menu bar full shape info: \(error)")
                }
            } receiveValue: { [weak self] data in
                self?.defaults.set(data, forKey: Defaults.menuBarFullShapeInfo)
            }
            .store(in: &c)

        $splitShapeInfo
            .encode(encoder: encoder)
            .sink { completion in
                if case .failure(let error) = completion {
                    Logger.appearanceManager.error("Error encoding menu bar split shape info: \(error)")
                }
            } receiveValue: { [weak self] data in
                self?.defaults.set(data, forKey: Defaults.menuBarSplitShapeInfo)
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
