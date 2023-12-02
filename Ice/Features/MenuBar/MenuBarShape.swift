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

struct MenuBarFullShapeInfo: Codable, Hashable {
    /// The leading end cap of the shape.
    var leadingEndCap: MenuBarEndCap
    /// The trailing end cap of the shape.
    var trailingEndCap: MenuBarEndCap
}

extension MenuBarFullShapeInfo {
    static let `default` = MenuBarFullShapeInfo(
        leadingEndCap: .square,
        trailingEndCap: .square
    )
}

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

enum MenuBarShapeKind: Codable, Hashable, CaseIterable {
    /// A shape that takes up the full menu bar.
    case full
    /// A shape that splits the menu bar between its leading
    /// and trailing sides.
    case split
}
