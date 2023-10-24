//
//  ColorAverage.swift
//  Ice
//

import CoreGraphics

/// An algorithm used to calculate the average color of the pixels
/// in an image.
enum ColorAverageAlgorithm {
    /// The average is calculated by summing each color component.
    case simple
    /// The average is calculated as the square root of the result
    /// of summing, then squaring each color component.
    case squareRoot
}

/// Constants that impact the accuracy and performance of a color
/// averaging algorithm.
enum ColorAverageAccuracy {
    /// The image is sampled at a low resolution, reducing the result's
    /// accuracy, but greatly improving the algorithm's performance.
    case low
    /// The image is sampled at a medium resolution, somewhat reducing the
    /// result's accuracy, but improving the algorithm's performance.
    case medium
    /// The image is sampled at a high resolution, producing a result that
    /// closely resembles the average color of the image.
    case high
    /// No resampling is applied to the image, producing a result that is
    /// the exact average color of the image.
    case exact
}

/// Options that affect the output of a color averaging algorithm.
struct ColorAverageOptions: OptionSet {
    let rawValue: Int

    /// The alpha component of the result is ignored and replaced
    /// with a value of `1`.
    static let ignoreAlpha = ColorAverageOptions(rawValue: 1 << 0)
}

/// Amounts to shift a pixel value to get the correct color components.
private enum Shift: UInt32 {
    /// Shift for the alpha component.
    case alpha = 0x18
    /// Shift for the red component.
    case red   = 0x10
    /// Shift for the green component.
    case green = 0x08
    /// Shift for the blue component.
    case blue  = 0x00
}

extension CGImage {
    /// Computes and returns the average color of the image.
    ///
    /// - Parameters:
    ///   - accuracy: The accuracy of the algorithm.
    ///   - algorithm: The algorithm used to compute the average.
    ///   - options: Options that further specify how the average
    ///     should be computed.
    ///   - alphaThreshold: An alpha value below which pixels should
    ///     be ignored. Pixels whose alpha component is less than
    ///     this value are not used in the computation.
    func averageColor(
        accuracy: ColorAverageAccuracy,
        algorithm: ColorAverageAlgorithm,
        options: ColorAverageOptions = [],
        alphaThreshold: CGFloat = 0.5
    ) -> CGColor? {
        // resize the image based on the accuracy; smaller images remove
        // more pixels, decreasing accuracy, but increasing performance
        let size = computeSize(for: accuracy)

        guard
            let context = createContext(size: size),
            let data = createImageData(context: context)
        else {
            return nil
        }

        let width = Int(size.width)
        let height = Int(size.height)

        // convert the alpha threshold to an integer, multiplied by 255;
        // pixels with an alpha component below this value are excluded
        // from the average
        let alphaThreshold = Int(alphaThreshold * 255)

        // start with a full pixel count; if any pixels are skipped,
        // the count is decremented accordingly
        var pixelCount = width * height

        // start with the totals zero'd out
        var totalRed = 0
        var totalGreen = 0
        var totalBlue = 0
        var totalAlpha = 0

        for column in 0..<width {
            for row in 0..<height {
                let pixel = data[(row * width) + column]

                // check alpha before computing other components
                let alphaComponent = computeComponent(pixel: pixel, shift: .alpha)
                guard alphaComponent >= alphaThreshold else {
                    pixelCount -= 1 // don't include this pixel
                    continue
                }

                let redComponent = computeComponent(pixel: pixel, shift: .red)
                let greenComponent = computeComponent(pixel: pixel, shift: .green)
                let blueComponent = computeComponent(pixel: pixel, shift: .blue)

                // sum the red, green, blue, and alpha components
                switch algorithm {
                case .simple:
                    totalRed += Int(redComponent)
                    totalGreen += Int(greenComponent)
                    totalBlue += Int(blueComponent)
                    totalAlpha += Int(alphaComponent)
                case .squareRoot:
                    totalRed += Int(pow(CGFloat(redComponent), 2))
                    totalGreen += Int(pow(CGFloat(greenComponent), 2))
                    totalBlue += Int(pow(CGFloat(blueComponent), 2))
                    totalAlpha += Int(pow(CGFloat(alphaComponent), 2))
                }
            }
        }

        let averageRed: CGFloat
        let averageGreen: CGFloat
        let averageBlue: CGFloat
        let averageAlpha: CGFloat

        // compute the averages of the summed components
        switch algorithm {
        case .simple:
            averageRed = CGFloat(totalRed) / CGFloat(pixelCount)
            averageGreen = CGFloat(totalGreen) / CGFloat(pixelCount)
            averageBlue = CGFloat(totalBlue) / CGFloat(pixelCount)
            averageAlpha = CGFloat(totalAlpha) / CGFloat(pixelCount)
        case .squareRoot:
            averageRed = sqrt(CGFloat(totalRed) / CGFloat(pixelCount))
            averageGreen = sqrt(CGFloat(totalGreen) / CGFloat(pixelCount))
            averageBlue = sqrt(CGFloat(totalBlue) / CGFloat(pixelCount))
            averageAlpha = sqrt(CGFloat(totalAlpha) / CGFloat(pixelCount))
        }

        // divide each component by 255 to convert to floating point
        let red = averageRed / 255
        let green = averageGreen / 255
        let blue = averageBlue / 255
        let alpha: CGFloat = if options.contains(.ignoreAlpha) {
            1.0
        } else {
            averageAlpha / 255
        }

        return CGColor(red: red, green: green, blue: blue, alpha: alpha)
    }

    /// Computes a new size for the image, based on the given accuracy.
    private func computeSize(for accuracy: ColorAverageAccuracy) -> CGSize {
        // get the image's maximum dimension, limited to 1000;
        // use a lazy var to avoid unnecessary allocation if the
        // dimension isn't needed
        lazy var maxDimension = CGFloat(max(width, height, 1000))
        switch accuracy {
        case .low:
            // size should be no more than 10x10
            maxDimension /= 100
            return CGSize(width: maxDimension, height: maxDimension)
        case .medium:
            // size should be no more than 100x100
            maxDimension /= 10
            return CGSize(width: maxDimension, height: maxDimension)
        case .high:
            // size should be no more than 1000x1000
            return CGSize(width: maxDimension, height: maxDimension)
        case .exact:
            // ignore the maximum dimension and return the exact
            // size of the image
            return CGSize(width: width, height: height)
        }
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
        return rawData.bindMemory(
            to: UInt32.self,
            capacity: context.width * context.height
        )
    }

    /// Computes the value of a color component for the given pixel value,
    /// shifting its value to the right by the given amount in order to get
    /// the correct color component.
    private func computeComponent(pixel: UInt32, shift: Shift) -> UInt8 {
        UInt8((pixel >> shift.rawValue) & 255)
    }
}
