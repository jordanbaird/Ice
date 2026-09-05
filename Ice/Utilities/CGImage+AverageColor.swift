//
//  CGImage+AverageColor.swift
//  Ice
//

import CoreGraphics

extension CGImage {
    // MARK: Color Averaging

    /// Options that affect how colors are processed when computing
    /// an average color.
    struct ColorAveragingOption: OptionSet {
        let rawValue: Int

        /// Returns an opaque color instead of averaging the alpha component.
        static let ignoreAlpha = ColorAveragingOption(rawValue: 1 << 0)
    }

    /// Computes and returns the average color of the image.
    ///
    /// - Parameters:
    ///   - colorSpace: The color space used to process the colors in the image.
    ///     The returned color also uses this color space. Must be an RGB color
    ///     space, or this parameter is ignored.
    ///   - alphaThreshold: An alpha value below which pixels should be ignored.
    ///     Pixels with an alpha component greater than or equal to this value
    ///     contribute to the average.
    ///   - option: Options for computing the color.
    func averageColor(using colorSpace: CGColorSpace? = nil, alphaThreshold: CGFloat = 0.5, option: ColorAveragingOption = []) -> CGColor? {
        guard alphaThreshold.isFinite else { return nil }
        func createPixelData(width: Int, height: Int, colorSpace: CGColorSpace) -> [UInt32]? {
            guard width > 0 && height > 0 else {
                return nil
            }
            var data = [UInt32](repeating: 0, count: width * height)
            guard let context = CGContext(
                data: &data,
                width: width,
                height: height,
                bitsPerComponent: 8,
                bytesPerRow: width * 4,
                space: colorSpace,
                bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue
            ) else {
                return nil
            }
            context.draw(self, in: CGRect(x: 0, y: 0, width: width, height: height))
            return data
        }

        func computeComponent(pixel: UInt32, shift: UInt32) -> UInt64 {
            UInt64((pixel >> shift) & 255)
        }

        let colorSpace: CGColorSpace = {
            if let colorSpace, colorSpace.model == .rgb {
                return colorSpace
            }
            if let colorSpace = self.colorSpace, colorSpace.model == .rgb {
                return colorSpace
            }
            if let colorSpace = CGColorSpace(name: CGColorSpace.displayP3) {
                return colorSpace
            }
            return CGColorSpaceCreateDeviceRGB()
        }()

        // Resize the image for better performance.
        let width = min(width, 10)
        let height = min(height, 10)

        guard let pixelData = createPixelData(width: width, height: height, colorSpace: colorSpace) else {
            return nil
        }

        // Convert the alpha threshold to a valid component for comparison.
        let alphaThreshold = UInt64((min(max(alphaThreshold, 0), 1) * 255).rounded(.toNearestOrAwayFromZero))

        var count = UInt64(width * height)
        var totals: (r: UInt64, g: UInt64, b: UInt64, a: UInt64) = (0, 0, 0, 0)

        for column in 0..<width {
            for row in 0..<height {
                let pixel = pixelData[(row * width) + column]

                // Check alpha before computing other components.
                let alpha = computeComponent(pixel: pixel, shift: 24)

                guard alpha >= alphaThreshold else {
                    count -= 1 // Don't include this pixel.
                    continue
                }

                totals.r += computeComponent(pixel: pixel, shift: 16)
                totals.g += computeComponent(pixel: pixel, shift: 8)
                totals.b += computeComponent(pixel: pixel, shift: 0)
                totals.a += alpha
            }
        }

        // No qualifying pixels means no average, not a color containing NaN.
        guard count > 0 else { return nil }

        // Components are currently in integer format (0 to 255), but need
        // to be converted to floating point (0 to 1). Makes more sense to
        // scale the count up to match the components, rather than scale
        // the components down to match the count.
        let scaledCount = CGFloat(count * 255)

        var components: [CGFloat] = [
            CGFloat(totals.r) / scaledCount,
            CGFloat(totals.g) / scaledCount,
            CGFloat(totals.b) / scaledCount,
            option.contains(.ignoreAlpha) ? 1 : CGFloat(totals.a) / scaledCount,
        ]

        return CGColor(colorSpace: colorSpace, components: &components)
    }
}
