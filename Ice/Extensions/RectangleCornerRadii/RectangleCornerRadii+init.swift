//
//  RectangleCornerRadii+init.swift
//  Ice
//

import SwiftUI

extension RectangleCornerRadii {
    /// Creates a new set of radii for a rectangle with the given leading and trailing edges.
    ///
    /// - Parameters:
    ///   - leading: The radius of the corners on the leading edge.
    ///   - trailing: The radius of the corners on the trailing edge.
    init(leading: CGFloat = 0, trailing: CGFloat = 0) {
        self.init(topLeading: leading, bottomLeading: leading, bottomTrailing: trailing, topTrailing: trailing)
    }
}
