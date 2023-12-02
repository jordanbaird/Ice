//
//  MenuBarShape.swift
//  Ice
//

import CoreGraphics

/// Information for an end cap in a menu bar shape.
struct MenuBarEndCapInfo: Codable, Hashable {
    /// The kind of the end cap.
    enum Kind: Int, Codable, Hashable {
        case rectangle = 0
        case roundedRectangle = 1
        case capsule = 2
    }

    /// The kind of the end cap.
    var kind: Kind

    /// The corner radius of the leading end cap.
    ///
    /// - Note: The corner radius is only applied when ``kind-swift.property``
    ///   is ``Kind-swift.enum/roundedRectangle``.
    var leadingCornerRadius: CGFloat

    /// The corner radius of the trailing end cap.
    ///
    /// - Note: The corner radius is only applied when ``kind-swift.property``
    ///   is ``Kind-swift.enum/roundedRectangle``.
    var trailingCornerRadius: CGFloat
}

struct MenuBarShapeInfo: Codable, Hashable {
    /// Information for the leading end cap of the shape.
    var leadingEndCap: MenuBarEndCapInfo
    /// Information for the trailing end cap of the shape.
    var trailingEndCap: MenuBarEndCapInfo
}

enum MenuBarShape: Codable, Hashable {
    /// A shape that takes up the full menu bar.
    case full(MenuBarShapeInfo)
    /// A shape that splits the menu bar between its leading
    /// and trailing sides.
    case split(MenuBarShapeInfo, MenuBarShapeInfo)
}

extension MenuBarShape {
    /// The default menu bar shape.
    static let defaultShape = MenuBarShape.full(
        MenuBarShapeInfo(
            leadingEndCap: MenuBarEndCapInfo(kind: .rectangle, leadingCornerRadius: 0, trailingCornerRadius: 5),
            trailingEndCap: MenuBarEndCapInfo(kind: .rectangle, leadingCornerRadius: 5, trailingCornerRadius: 0)
        )
    )
}
