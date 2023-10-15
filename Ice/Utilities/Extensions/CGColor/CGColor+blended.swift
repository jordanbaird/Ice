//
//  CGColor+blended.swift
//  Ice
//

import CoreGraphics

extension CGColor {
    /// Creates a new color whose component values are a weighted sum of
    /// the current and specified colors.
    ///
    /// This method converts both colors to RGB before blending. If either
    /// color is unable to be converted, this method returns `nil`.
    ///
    /// - Parameters:
    ///   - fraction: The amount of `color` to blend with the current color.
    ///   - color: The color to blend with the current color.
    ///
    /// - Returns: The blended color, if successful. Otherwise `nil`.
    func blended(withFraction fraction: CGFloat, of color: CGColor) -> CGColor? {
        let deviceRGB = CGColorSpaceCreateDeviceRGB()
        guard
            let color1 = self.converted(to: deviceRGB, intent: .defaultIntent, options: nil),
            let color2 = color.converted(to: deviceRGB, intent: .defaultIntent, options: nil),
            color1.numberOfComponents == 4,
            color2.numberOfComponents == 4,
            let c1 = color1.components,
            let c2 = color2.components
        else {
            return nil
        }

        let (r1, g1, b1, a1) = (c1[0], c1[1], c1[2], c1[3])
        let (r2, g2, b2, a2) = (c2[0], c2[1], c2[2], c2[3])

        let clampedFraction = min(max(fraction, 0), 1)
        let inverseFraction = 1 - clampedFraction

        var components = [
            (r1 * inverseFraction).addingProduct(r2, clampedFraction),
            (g1 * inverseFraction).addingProduct(g2, clampedFraction),
            (b1 * inverseFraction).addingProduct(b2, clampedFraction),
            (a1 * inverseFraction).addingProduct(a2, clampedFraction),
        ]

        return CGColor(colorSpace: deviceRGB, components: &components)
    }
}
