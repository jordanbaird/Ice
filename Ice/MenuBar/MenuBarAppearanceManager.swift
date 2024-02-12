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

    private var cancellables = Set<AnyCancellable>()

    private let encoder: JSONEncoder
    private let decoder: JSONDecoder

    private let defaults: UserDefaults

    private(set) weak var menuBarManager: MenuBarManager?

    private var appearancePanels = Set<MenuBarAppearancePanel>()

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
        configureAppearancePanels()
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

        $hasShadow
            .receive(on: DispatchQueue.main)
            .sink { [weak self] hasShadow in
                guard let self else {
                    return
                }
                defaults.set(hasShadow, forKey: Defaults.menuBarHasShadow)
            }
            .store(in: &c)

        $hasBorder
            .receive(on: DispatchQueue.main)
            .sink { [weak self] hasBorder in
                guard let self else {
                    return
                }
                defaults.set(hasBorder, forKey: Defaults.menuBarHasBorder)
            }
            .store(in: &c)

        $borderColor
            .receive(on: DispatchQueue.main)
            .sink { [weak self] borderColor in
                guard let self else {
                    return
                }
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
            .sink { [weak self] borderWidth in
                guard let self else {
                    return
                }
                defaults.set(borderWidth, forKey: Defaults.menuBarBorderWidth)
            }
            .store(in: &c)

        $tintKind
            .receive(on: DispatchQueue.main)
            .sink { [weak self] tintKind in
                guard let self else {
                    return
                }
                defaults.set(tintKind.rawValue, forKey: Defaults.menuBarTintKind)
            }
            .store(in: &c)

        $tintColor
            .receive(on: DispatchQueue.main)
            .sink { [weak self] tintColor in
                guard let self else {
                    return
                }
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
            } receiveValue: { [weak self] data in
                guard let self else {
                    return
                }
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
                guard let self else {
                    return
                }
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
            } receiveValue: { [weak self] data in
                guard let self else {
                    return
                }
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
            } receiveValue: { [weak self] data in
                guard let self else {
                    return
                }
                defaults.set(data, forKey: Defaults.menuBarSplitShapeInfo)
            }
            .store(in: &c)

        cancellables = c
    }

    private func configureAppearancePanels() {
        var appearancePanels = Set<MenuBarAppearancePanel>()
        for screen in NSScreen.screens {
            let panel = MenuBarAppearancePanel(appearanceManager: self, owningScreen: screen)
            panel.show()
            appearancePanels.insert(panel)
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
