//
//  MenuBarShapes.swift
//  Ice
//

import SwiftUI

/// An end cap in a menu bar shape.
enum MenuBarEndCap: Int, CaseIterable, Codable, Hashable {
    /// An end cap with a square shape.
    case square = 0
    /// An end cap with a rounded shape.
    case round = 1
}

/// A type that specifies a custom shape kind for the menu bar.
enum MenuBarShapeKind: Int, CaseIterable, Codable, Identifiable {
    /// The menu bar does not use a custom shape.
    case noShape = 0
    /// A custom shape that takes up the full menu bar.
    case full = 1
    /// A custom shape that splits the menu bar between its leading
    /// and trailing sides.
    case split = 2

    var id: Int { rawValue }

    /// Localized string key representation.
    var localized: LocalizedStringKey {
        switch self {
        case .noShape: "None"
        case .full: "Full"
        case .split: "Split"
        }
    }
}

/// Information for the ``MenuBarShapeKind/full`` menu bar shape kind.
struct MenuBarFullShapeInfo: Codable, Hashable {
    /// The leading end cap of the shape.
    var leadingEndCap: MenuBarEndCap
    /// The trailing end cap of the shape.
    var trailingEndCap: MenuBarEndCap
}

extension MenuBarFullShapeInfo {
    var hasRoundedShape: Bool {
        leadingEndCap == .round || trailingEndCap == .round
    }
}

extension MenuBarFullShapeInfo {
    static let `default` = MenuBarFullShapeInfo(leadingEndCap: .round, trailingEndCap: .round)
}

/// Information for the ``MenuBarShapeKind/split`` menu bar shape kind.
struct MenuBarSplitShapeInfo: Codable, Hashable {
    /// The leading information of the shape.
    var leading: MenuBarFullShapeInfo
    /// The trailing information of the shape.
    var trailing: MenuBarFullShapeInfo
}

extension MenuBarSplitShapeInfo {
    var hasRoundedShape: Bool {
        leading.hasRoundedShape || trailing.hasRoundedShape
    }
}

extension MenuBarSplitShapeInfo {
    static let `default` = MenuBarSplitShapeInfo(leading: .default, trailing: .default)
}
