//
//  MenuBarAppearanceConfiguration.swift
//  Ice
//

import CoreGraphics
import Foundation

/// Configuration for the menu bar's appearance.
struct MenuBarAppearanceConfiguration: Hashable {
    var hasShadow: Bool
    var hasBorder: Bool
    var isInset: Bool
    var borderColor: CGColor
    var borderWidth: Double
    var shapeKind: MenuBarShapeKind
    var fullShapeInfo: MenuBarFullShapeInfo
    var splitShapeInfo: MenuBarSplitShapeInfo
    var tintKind: MenuBarTintKind
    var tintColor: CGColor
    var tintGradient: CustomGradient

    var hasRoundedShape: Bool {
        switch shapeKind {
        case .none: false
        case .full: fullShapeInfo.hasRoundedShape
        case .split: splitShapeInfo.hasRoundedShape
        }
    }

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
        isInset: true,
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
        case isInset
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
            hasShadow: container.decodeIfPresent(Bool.self, forKey: .hasShadow) ?? Self.defaultConfiguration.hasShadow,
            hasBorder: container.decodeIfPresent(Bool.self, forKey: .hasBorder) ?? Self.defaultConfiguration.hasBorder,
            isInset: container.decodeIfPresent(Bool.self, forKey: .isInset) ?? Self.defaultConfiguration.isInset,
            borderColor: container.decodeIfPresent(CodableColor.self, forKey: .borderColor)?.cgColor ?? Self.defaultConfiguration.borderColor,
            borderWidth: container.decodeIfPresent(Double.self, forKey: .borderWidth) ?? Self.defaultConfiguration.borderWidth,
            shapeKind: container.decodeIfPresent(MenuBarShapeKind.self, forKey: .shapeKind) ?? Self.defaultConfiguration.shapeKind,
            fullShapeInfo: container.decodeIfPresent(MenuBarFullShapeInfo.self, forKey: .fullShapeInfo) ?? Self.defaultConfiguration.fullShapeInfo,
            splitShapeInfo: container.decodeIfPresent(MenuBarSplitShapeInfo.self, forKey: .splitShapeInfo) ?? Self.defaultConfiguration.splitShapeInfo,
            tintKind: container.decodeIfPresent(MenuBarTintKind.self, forKey: .tintKind) ?? Self.defaultConfiguration.tintKind,
            tintColor: container.decodeIfPresent(CodableColor.self, forKey: .tintColor)?.cgColor ?? Self.defaultConfiguration.tintColor,
            tintGradient: container.decodeIfPresent(CustomGradient.self, forKey: .tintGradient) ?? Self.defaultConfiguration.tintGradient
        )
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(hasShadow, forKey: .hasShadow)
        try container.encode(hasBorder, forKey: .hasBorder)
        try container.encode(isInset, forKey: .isInset)
        try container.encode(CodableColor(cgColor: borderColor), forKey: .borderColor)
        try container.encode(borderWidth, forKey: .borderWidth)
        try container.encode(shapeKind, forKey: .shapeKind)
        try container.encode(fullShapeInfo, forKey: .fullShapeInfo)
        try container.encode(splitShapeInfo, forKey: .splitShapeInfo)
        try container.encode(tintKind, forKey: .tintKind)
        try container.encode(CodableColor(cgColor: tintColor), forKey: .tintColor)
        try container.encode(tintGradient, forKey: .tintGradient)
    }
}
