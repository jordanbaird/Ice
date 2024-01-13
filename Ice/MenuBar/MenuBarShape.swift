//
//  MenuBarShape.swift
//  Ice
//

import CoreGraphics

/// An end cap in a menu bar shape.
enum MenuBarEndCap: Int, Codable, Hashable, CaseIterable {
    case square = 0
    case round = 1
}

/// Information that specifies the ``MenuBarShapeKind/full`` case.
struct MenuBarFullShapeInfo: Codable, Hashable {
    /// The leading end cap of the shape.
    var leadingEndCap: MenuBarEndCap
    /// The trailing end cap of the shape.
    var trailingEndCap: MenuBarEndCap
}

extension MenuBarFullShapeInfo {
    static let `default` = MenuBarFullShapeInfo(
        leadingEndCap: .round,
        trailingEndCap: .round
    )
}

/// Information that specifies the ``MenuBarShapeKind/split`` case.
struct MenuBarSplitShapeInfo: Codable, Hashable {
    /// The leading information of the shape.
    var leading: MenuBarFullShapeInfo
    /// The trailing information of the shape.
    var trailing: MenuBarFullShapeInfo
}

extension MenuBarSplitShapeInfo {
    static let `default` = MenuBarSplitShapeInfo(
        leading: .default,
        trailing: .default
    )
}

/// A type that specifies a custom shape kind for the menu bar.
enum MenuBarShapeKind: Int, Codable, Hashable, CaseIterable {
    /// The menu bar does not use a custom shape.
    case none = 0
    /// A custom shape that takes up the full menu bar.
    case full = 1
    /// A custom shape that splits the menu bar between
    /// its leading and trailing sides.
    case split = 2
}
