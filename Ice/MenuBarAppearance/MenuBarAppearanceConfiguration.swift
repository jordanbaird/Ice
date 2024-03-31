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

    /// Creates a configuration by migrating from the deprecated
    /// appearance-related keys stored in `UserDefaults`, storing
    /// the new configuration and deleting the deprecated keys.
    static func migrate(encoder: JSONEncoder, decoder: JSONDecoder) throws -> Self {
        // try to load an already-migrated configuration first;
        // otherwise, load each value from the deprecated keys
        if let data = Defaults.data(forKey: .menuBarAppearanceConfiguration) {
            return try decoder.decode(Self.self, from: data)
        } else {
            var configuration = Self.defaultConfiguration

            Defaults.ifPresent(key: .menuBarHasShadow, assign: &configuration.hasShadow)
            Defaults.ifPresent(key: .menuBarHasBorder, assign: &configuration.hasBorder)
            Defaults.ifPresent(key: .menuBarBorderWidth, assign: &configuration.borderWidth)
            Defaults.ifPresent(key: .menuBarTintKind) { rawValue in
                if let tintKind = MenuBarTintKind(rawValue: rawValue) {
                    configuration.tintKind = tintKind
                }
            }

            if let borderColorData = Defaults.data(forKey: .menuBarBorderColor) {
                configuration.borderColor = try decoder.decode(CodableColor.self, from: borderColorData).cgColor
            }
            if let tintColorData = Defaults.data(forKey: .menuBarTintColor) {
                configuration.tintColor = try decoder.decode(CodableColor.self, from: tintColorData).cgColor
            }
            if let tintGradientData = Defaults.data(forKey: .menuBarTintGradient) {
                configuration.tintGradient = try decoder.decode(CustomGradient.self, from: tintGradientData)
            }
            if let shapeKindData = Defaults.data(forKey: .menuBarShapeKind) {
                configuration.shapeKind = try decoder.decode(MenuBarShapeKind.self, from: shapeKindData)
            }
            if let fullShapeData = Defaults.data(forKey: .menuBarFullShapeInfo) {
                configuration.fullShapeInfo = try decoder.decode(MenuBarFullShapeInfo.self, from: fullShapeData)
            }
            if let splitShapeData = Defaults.data(forKey: .menuBarSplitShapeInfo) {
                configuration.splitShapeInfo = try decoder.decode(MenuBarSplitShapeInfo.self, from: splitShapeData)
            }

            // store the configuration to complete the migration
            let configurationData = try encoder.encode(configuration)
            Defaults.set(configurationData, forKey: .menuBarAppearanceConfiguration)

            // remove the deprecated keys
            let keys: [Defaults.Key] = [
                .menuBarHasShadow,
                .menuBarHasBorder,
                .menuBarBorderWidth,
                .menuBarTintKind,
                .menuBarBorderColor,
                .menuBarTintColor,
                .menuBarTintGradient,
                .menuBarShapeKind,
                .menuBarFullShapeInfo,
                .menuBarSplitShapeInfo,
            ]
            for key in keys {
                Defaults.removeObject(forKey: key)
            }

            return configuration
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
