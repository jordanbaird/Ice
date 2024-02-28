//
//  CGColor+codable.swift
//  Ice
//

import CoreGraphics

extension CGColor {
    /// A `Codable` wrapper around this color.
    var codable: CodableColor {
        CodableColor(cgColor: self)
    }
}
