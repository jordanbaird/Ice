//
//  CGImage+averageColor.swift
//  Ice
//

import CoreGraphics

/// Constants that determine the resolution of a color averaging algorithm.
enum ColorAverageResolution {
    /// Images are sampled at low resolution, reducing accuracy, but improving performance.
    case low
    /// Images are sampled at medium resolution, with nominal accuracy and performance.
    case medium
    /// Images are sampled at high resolution, improving accuracy, but reducing performance.
    case high
}

/// Options that affect the output of a color averaging algorithm.
struct ColorAverageOptions: OptionSet {
    let rawValue: Int

    /// The alpha component of the result is ignored and replaced with a value of `1`.
    static let ignoreAlpha = ColorAverageOptions(rawValue: 1 << 0)
}

/// A color component in the ARGB color space.
private enum ARGBComponent: UInt32 {
    case alpha = 0x18
    case red   = 0x10
    case green = 0x08
    case blue  = 0x00
}

extension CGImage {
    /// Computes and returns the average color of the image.
    ///
    /// - Parameters:
    ///   - resolution: The resolution of the algorithm.
    ///   - options: Options that further specify how the average should be computed.
    ///   - alphaThreshold: An alpha value below which pixels should be ignored. Pixels
    ///     whose alpha component is less than this value are not used in the computation.
    func averageColor(
        resolution: ColorAverageResolution = .medium,
        options: ColorAverageOptions = [],
        alphaThreshold: CGFloat = 0.5
    ) -> CGColor? {
        // resize the image based on the resolution; smaller images remove more pixels,
        // decreasing accuracy, but increasing performance
        let size = switch resolution {
        case .low:
            CGSize(width: 10, height: 10)
        case .medium:
            CGSize(width: 50, height: 50)
        case .high:
            CGSize(width: 100, height: 100)
        }

        guard
            let context = createContext(size: size),
            let data = createImageData(context: context)
        else {
            return nil
        }

        let width = Int(size.width)
        let height = Int(size.height)

        // convert the alpha threshold to an integer, multiplied by 255; pixels with
        // an alpha component below this value are excluded from the average
        let alphaThreshold = Int(alphaThreshold * 255)

        // start with a full pixel count; if any pixels are skipped, the count is
        // decremented accordingly
        var pixelCount = width * height

        // start with the totals zeroed out
        var totalRed = 0
        var totalGreen = 0
        var totalBlue = 0
        var totalAlpha = 0

        for column in 0..<width {
            for row in 0..<height {
                let pixel = data[(row * width) + column]

                // check alpha before computing other components
                let alphaComponent = computeComponentValue(.alpha, for: pixel)

                guard alphaComponent >= alphaThreshold else {
                    pixelCount -= 1 // don't include this pixel
                    continue
                }

                let redComponent = computeComponentValue(.red, for: pixel)
                let greenComponent = computeComponentValue(.green, for: pixel)
                let blueComponent = computeComponentValue(.blue, for: pixel)

                // sum the red, green, blue, and alpha components
                totalRed += redComponent
                totalGreen += greenComponent
                totalBlue += blueComponent
                totalAlpha += alphaComponent
            }
        }

        // compute the averages of the summed components
        let averageRed = CGFloat(totalRed) / CGFloat(pixelCount)
        let averageGreen = CGFloat(totalGreen) / CGFloat(pixelCount)
        let averageBlue = CGFloat(totalBlue) / CGFloat(pixelCount)
        let averageAlpha = CGFloat(totalAlpha) / CGFloat(pixelCount)

        // divide each component by 255 to convert to floating point
        let red = averageRed / 255
        let green = averageGreen / 255
        let blue = averageBlue / 255
        let alpha = options.contains(.ignoreAlpha) ? 1 : averageAlpha / 255

        return CGColor(red: red, green: green, blue: blue, alpha: alpha)
    }

    /// Creates a bitmap context for resizing the image to the given size.
    private func createContext(size: CGSize) -> CGContext? {
        let width = Int(size.width)
        let height = Int(size.height)
        let bytesPerRow = width * 4
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        let byteOrder = CGImageByteOrderInfo.order32Little.rawValue
        let alphaInfo = CGImageAlphaInfo.premultipliedFirst.rawValue
        return CGContext(
            data: nil,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: bytesPerRow,
            space: colorSpace,
            bitmapInfo: byteOrder | alphaInfo
        )
    }

    /// Draws the image into the given context and returns the raw data.
    private func createImageData(context: CGContext) -> UnsafeMutablePointer<UInt32>? {
        let rect = CGRect(x: 0, y: 0, width: context.width, height: context.height)
        context.draw(self, in: rect)
        guard let rawData = context.data else {
            return nil
        }
        return rawData.bindMemory(to: UInt32.self, capacity: context.width * context.height)
    }

    /// Computes the value of a color component for the given pixel value.
    private func computeComponentValue(_ component: ARGBComponent, for pixel: UInt32) -> Int {
        Int((pixel >> component.rawValue) & 255)
    }
}
