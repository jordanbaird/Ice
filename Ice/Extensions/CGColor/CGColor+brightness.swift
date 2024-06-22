//
//  CGColor+brightness.swift
//  Ice
//

import CoreGraphics

extension CGColor {
    /// Returns the brightness of the color.
    var brightness: CGFloat? {
        guard
            let rgb = converted(to: CGColorSpaceCreateDeviceRGB(), intent: .defaultIntent, options: nil),
            let components = rgb.components
        else {
            return nil
        }
        // algorithm from http://www.w3.org/WAI/ER/WD-AERT/#color-contrast
        return ((components[0] * 299) + (components[1] * 587) + (components[2] * 114)) / 1000
    }
}
