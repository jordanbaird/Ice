//
//  MenuBarAppearanceConfigurationV2.swift
//  Ice
//

import AppKit
import CoreGraphics
import Foundation

struct MenuBarAppearanceConfigurationV2: Hashable {
    var lightModeConfiguration: MenuBarAppearancePartialConfiguration
    var darkModeConfiguration: MenuBarAppearancePartialConfiguration
    var staticConfiguration: MenuBarAppearancePartialConfiguration
    var shapeKind: MenuBarShapeKind
    var fullShapeInfo: MenuBarFullShapeInfo
    var splitShapeInfo: MenuBarSplitShapeInfo
    var screenShapeInfo: ScreenShapeInfo
    var screenShapeOverrides: [String: ScreenShapeInfo]
    var isInset: Bool
    var isDynamic: Bool

    var hasRoundedShape: Bool {
        switch shapeKind {
        case .none: false
        case .full: fullShapeInfo.hasRoundedShape
        case .split: splitShapeInfo.hasRoundedShape
        }
    }

    var current: MenuBarAppearancePartialConfiguration {
        if isDynamic {
            switch SystemAppearance.current {
            case .light: lightModeConfiguration
            case .dark: darkModeConfiguration
            }
        } else {
            staticConfiguration
        }
    }
}

// MARK: Default Configuration
extension MenuBarAppearanceConfigurationV2 {
    static let defaultConfiguration = MenuBarAppearanceConfigurationV2(
        lightModeConfiguration: .defaultConfiguration,
        darkModeConfiguration: .defaultConfiguration,
        staticConfiguration: .defaultConfiguration,
        shapeKind: .none,
        fullShapeInfo: .default,
        splitShapeInfo: .default,
        screenShapeInfo: .default,
        screenShapeOverrides: [:],
        isInset: true,
        isDynamic: false
    )
}

// MARK: Screen shape helpers
extension MenuBarAppearanceConfigurationV2 {
    /// Returns the screen shape settings for the given screen, falling back
    /// to the default ``screenShapeInfo`` when there is no override.
    func effectiveScreenShapeInfo(for screen: NSScreen) -> ScreenShapeInfo {
        if let id = screen.stableIdentifier, let override = screenShapeOverrides[id] {
            return override
        }
        return screenShapeInfo
    }
}

extension MenuBarAppearanceConfigurationV2: Codable {
    private enum CodingKeys: CodingKey {
        case lightModeConfiguration
        case darkModeConfiguration
        case staticConfiguration
        case shapeKind
        case fullShapeInfo
        case splitShapeInfo
        case screenShapeInfo
        case screenShapeOverrides
        case isInset
        case isDynamic
    }

    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        try self.init(
            lightModeConfiguration: container.decodeIfPresent(MenuBarAppearancePartialConfiguration.self, forKey: .lightModeConfiguration) ?? Self.defaultConfiguration.lightModeConfiguration,
            darkModeConfiguration: container.decodeIfPresent(MenuBarAppearancePartialConfiguration.self, forKey: .darkModeConfiguration) ?? Self.defaultConfiguration.darkModeConfiguration,
            staticConfiguration: container.decodeIfPresent(MenuBarAppearancePartialConfiguration.self, forKey: .staticConfiguration) ?? Self.defaultConfiguration.staticConfiguration,
            shapeKind: container.decodeIfPresent(MenuBarShapeKind.self, forKey: .shapeKind) ?? Self.defaultConfiguration.shapeKind,
            fullShapeInfo: container.decodeIfPresent(MenuBarFullShapeInfo.self, forKey: .fullShapeInfo) ?? Self.defaultConfiguration.fullShapeInfo,
            splitShapeInfo: container.decodeIfPresent(MenuBarSplitShapeInfo.self, forKey: .splitShapeInfo) ?? Self.defaultConfiguration.splitShapeInfo,
            screenShapeInfo: container.decodeIfPresent(ScreenShapeInfo.self, forKey: .screenShapeInfo) ?? Self.defaultConfiguration.screenShapeInfo,
            screenShapeOverrides: container.decodeIfPresent([String: ScreenShapeInfo].self, forKey: .screenShapeOverrides) ?? Self.defaultConfiguration.screenShapeOverrides,
            isInset: container.decodeIfPresent(Bool.self, forKey: .isInset) ?? Self.defaultConfiguration.isInset,
            isDynamic: container.decodeIfPresent(Bool.self, forKey: .isDynamic) ?? Self.defaultConfiguration.isDynamic
        )
    }

    func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(lightModeConfiguration, forKey: .lightModeConfiguration)
        try container.encode(darkModeConfiguration, forKey: .darkModeConfiguration)
        try container.encode(staticConfiguration, forKey: .staticConfiguration)
        try container.encode(shapeKind, forKey: .shapeKind)
        try container.encode(fullShapeInfo, forKey: .fullShapeInfo)
        try container.encode(splitShapeInfo, forKey: .splitShapeInfo)
        try container.encode(screenShapeInfo, forKey: .screenShapeInfo)
        try container.encode(screenShapeOverrides, forKey: .screenShapeOverrides)
        try container.encode(isInset, forKey: .isInset)
        try container.encode(isDynamic, forKey: .isDynamic)
    }
}

// MARK: - MenuBarAppearancePartialConfiguration

struct MenuBarAppearancePartialConfiguration: Hashable {
    var hasShadow: Bool
    var hasBorder: Bool
    var borderColor: CGColor
    var borderWidth: Double
    var appearanceKind: MenuBarAppearanceKind
    var tintKind: MenuBarTintKind
    var tintColor: CGColor
    var tintGradient: CustomGradient
}

// MARK: Default Partial Configuration
extension MenuBarAppearancePartialConfiguration {
    static let defaultConfiguration = MenuBarAppearancePartialConfiguration(
        hasShadow: false,
        hasBorder: false,
        borderColor: .black,
        borderWidth: 1,
        appearanceKind: .none,
        tintKind: .solid,
        tintColor: CGColor(srgbRed: 0, green: 0, blue: 0, alpha: 1),
        tintGradient: .defaultMenuBarTint
    )
}

// MARK: MenuBarAppearancePartialConfiguration: Codable
extension MenuBarAppearancePartialConfiguration: Codable {
    private enum CodingKeys: CodingKey {
        case hasShadow
        case hasBorder
        case borderColor
        case borderWidth
        case shapeKind
        case fullShapeInfo
        case splitShapeInfo
        case appearanceKind
        case tintKind
        case tintColor
        case tintGradient
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let tintKind = try container.decodeIfPresent(MenuBarTintKind.self, forKey: .tintKind) ?? Self.defaultConfiguration.tintKind
        let appearanceKind: MenuBarAppearanceKind = {
            if let stored = try? container.decodeIfPresent(MenuBarAppearanceKind.self, forKey: .appearanceKind) {
                return stored
            }
            // Legacy data has no appearanceKind. Derive it: a stored tintKind of
            // .none means the user had no color treatment; .solid/.gradient maps
            // to the pre-existing overlay-style behavior, i.e. .tint.
            return tintKind == .none ? .none : .tint
        }()
        // Normalize legacy .none tintKind to .solid since the picker no longer
        // offers .none. The appearanceKind above carries the intent.
        let resolvedTintKind: MenuBarTintKind = tintKind == .none ? .solid : tintKind
        try self.init(
            hasShadow: container.decodeIfPresent(Bool.self, forKey: .hasShadow) ?? Self.defaultConfiguration.hasShadow,
            hasBorder: container.decodeIfPresent(Bool.self, forKey: .hasBorder) ?? Self.defaultConfiguration.hasBorder,
            borderColor: container.decodeIfPresent(CodableColor.self, forKey: .borderColor)?.cgColor ?? Self.defaultConfiguration.borderColor,
            borderWidth: container.decodeIfPresent(Double.self, forKey: .borderWidth) ?? Self.defaultConfiguration.borderWidth,
            appearanceKind: appearanceKind,
            tintKind: resolvedTintKind,
            tintColor: container.decodeIfPresent(CodableColor.self, forKey: .tintColor)?.cgColor ?? Self.defaultConfiguration.tintColor,
            tintGradient: container.decodeIfPresent(CustomGradient.self, forKey: .tintGradient) ?? Self.defaultConfiguration.tintGradient
        )
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(hasShadow, forKey: .hasShadow)
        try container.encode(hasBorder, forKey: .hasBorder)
        try container.encode(CodableColor(cgColor: borderColor), forKey: .borderColor)
        try container.encode(borderWidth, forKey: .borderWidth)
        try container.encode(appearanceKind, forKey: .appearanceKind)
        try container.encode(tintKind, forKey: .tintKind)
        try container.encode(CodableColor(cgColor: tintColor), forKey: .tintColor)
        try container.encode(tintGradient, forKey: .tintGradient)
    }
}
