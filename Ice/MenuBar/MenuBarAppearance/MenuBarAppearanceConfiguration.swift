//
//  MenuBarAppearanceConfiguration.swift
//  Ice
//

import CoreGraphics
import Foundation

/// Configuration for the menu bar's appearance.
struct MenuBarAppearanceConfiguration {
    var hasShadow: Bool
    var hasBorder: Bool
    var borderColor: CGColor
    var borderWidth: Double
    var shapeKind: MenuBarShapeKind
    var fullShapeInfo: MenuBarFullShapeInfo
    var splitShapeInfo: MenuBarSplitShapeInfo
    var tintKind: MenuBarTintKind
    var tintColor: CGColor
    var tintGradient: CustomGradient

    /// Creates a configuration with the given values.
    init(
        hasShadow: Bool,
        hasBorder: Bool,
        borderColor: CGColor,
        borderWidth: Double,
        shapeKind: MenuBarShapeKind,
        fullShapeInfo: MenuBarFullShapeInfo,
        splitShapeInfo: MenuBarSplitShapeInfo,
        tintKind: MenuBarTintKind,
        tintColor: CGColor,
        tintGradient: CustomGradient
    ) {
        self.hasShadow = hasShadow
        self.hasBorder = hasBorder
        self.borderColor = borderColor
        self.borderWidth = borderWidth
        self.shapeKind = shapeKind
        self.fullShapeInfo = fullShapeInfo
        self.splitShapeInfo = splitShapeInfo
        self.tintKind = tintKind
        self.tintColor = tintColor
        self.tintGradient = tintGradient
    }

    /// Creates a configuration by migrating from the deprecated
    /// appearance-related keys stored in `UserDefaults`, storing
    /// the new configuration and deleting the deprecated keys.
    init(
        migratingFrom defaults: UserDefaults,
        encoder: JSONEncoder,
        decoder: JSONDecoder
    ) throws {
        // try to load an already-migrated configuration first;
        // otherwise, load each value from the deprecated keys
        if let data = defaults.data(forKey: Defaults.menuBarAppearanceConfiguration) {
            self = try decoder.decode(Self.self, from: data)
        } else {
            self = .defaultConfiguration

            defaults.ifPresent(key: Defaults.menuBarHasShadow, assign: &hasShadow)
            defaults.ifPresent(key: Defaults.menuBarHasBorder, assign: &hasBorder)
            defaults.ifPresent(key: Defaults.menuBarBorderWidth, assign: &borderWidth)
            defaults.ifPresent(key: Defaults.menuBarTintKind) { rawValue in
                if let tintKind = MenuBarTintKind(rawValue: rawValue) {
                    self.tintKind = tintKind
                }
            }

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

            // store the configuration to complete the migration
            let configurationData = try encoder.encode(self)
            defaults.set(configurationData, forKey: Defaults.menuBarAppearanceConfiguration)

            // remove the deprecated keys
            let keys = [
                Defaults.menuBarHasShadow,
                Defaults.menuBarHasBorder,
                Defaults.menuBarBorderWidth,
                Defaults.menuBarTintKind,
                Defaults.menuBarBorderColor,
                Defaults.menuBarTintColor,
                Defaults.menuBarTintGradient,
                Defaults.menuBarShapeKind,
                Defaults.menuBarFullShapeInfo,
                Defaults.menuBarSplitShapeInfo,
            ]
            for key in keys {
                defaults.removeObject(forKey: key)
            }
        }
    }
}

// MARK: Default Configuration
extension MenuBarAppearanceConfiguration {
    static let defaultConfiguration = MenuBarAppearanceConfiguration(
        hasShadow: false,
        hasBorder: false,
        borderColor: .black,
        borderWidth: 1,
        shapeKind: .none,
        fullShapeInfo: .default,
        splitShapeInfo: .default,
        tintKind: .none,
        tintColor: .black,
        tintGradient: .defaultMenuBarTint
    )
}

// MARK: MenuBarAppearanceConfiguration: Codable
extension MenuBarAppearanceConfiguration: Codable {
    private enum CodingKeys: CodingKey {
        case hasShadow
        case hasBorder
        case borderColor
        case borderWidth
        case shapeKind
        case fullShapeInfo
        case splitShapeInfo
        case tintKind
        case tintColor
        case tintGradient
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        try self.init(
            hasShadow: container.decode(Bool.self, forKey: .hasShadow),
            hasBorder: container.decode(Bool.self, forKey: .hasBorder),
            borderColor: container.decode(CodableColor.self, forKey: .borderColor).cgColor,
            borderWidth: container.decode(Double.self, forKey: .borderWidth),
            shapeKind: container.decode(MenuBarShapeKind.self, forKey: .shapeKind),
            fullShapeInfo: container.decode(MenuBarFullShapeInfo.self, forKey: .fullShapeInfo),
            splitShapeInfo: container.decode(MenuBarSplitShapeInfo.self, forKey: .splitShapeInfo),
            tintKind: container.decode(MenuBarTintKind.self, forKey: .tintKind),
            tintColor: container.decode(CodableColor.self, forKey: .tintColor).cgColor,
            tintGradient: container.decode(CustomGradient.self, forKey: .tintGradient)
        )
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(hasShadow, forKey: .hasShadow)
        try container.encode(hasBorder, forKey: .hasBorder)
        try container.encode(borderColor.codable, forKey: .borderColor)
        try container.encode(borderWidth, forKey: .borderWidth)
        try container.encode(shapeKind, forKey: .shapeKind)
        try container.encode(fullShapeInfo, forKey: .fullShapeInfo)
        try container.encode(splitShapeInfo, forKey: .splitShapeInfo)
        try container.encode(tintKind, forKey: .tintKind)
        try container.encode(tintColor.codable, forKey: .tintColor)
        try container.encode(tintGradient, forKey: .tintGradient)
    }
}
