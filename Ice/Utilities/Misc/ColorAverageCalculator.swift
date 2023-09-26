//
//  ColorAverageCalculator.swift
//  Ice
//

import Cocoa

/// A type that calculates the average color of the pixels in an image.
class ColorAverageCalculator {
    /// An algorithm used to calculate the average color of the pixels
    /// in an image.
    enum Algorithm {
        /// The average is calculated by summing each color component.
        case simple
        /// The average is calculated as the square root of the result
        /// of summing, then squaring each color component.
        case squareRoot
    }

    /// Constants that impact the accuracy and performance of a color
    /// averaging algorithm.
    enum Accuracy {
        /// The image is sampled at a low resolution, reducing the result's
        /// accuracy, but greatly improving the algorithm's performance.
        case low
        /// The image is sampled at a medium resolution, somewhat reducing
        /// result's accuracy, but improving the algorithm's performance.
        case medium
        /// The image is sampled at a high resolution, producing a result
        /// that closely resembles the average color of the image.
        case high
        /// No resampling is applied to the image, producing a result that
        /// is the exact average color of the image.
        case exact
    }

    /// A type that contains the red, green, blue, and alpha components
    /// for a color.
    struct ColorComponents {
        /// The red component.
        var red: CGFloat
        /// The green component.
        var green: CGFloat
        /// The blue component.
        var blue: CGFloat
        /// The alpha component.
        var alpha: CGFloat
    }

    /// Amounts to shift a pixel value to get the correct color component.
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

    /// The accuracy of the calculator's algorithm.
    var accuracy: Accuracy

    /// The algorithm that the calculator uses to compute average colors.
    var algorithm: Algorithm

    /// A threshold that determines which pixels in an image are included
    /// in the average.
    ///
    /// Pixels with an alpha component that is below the threshold are
    /// not included in the average.
    var alphaThreshold: CGFloat

    /// Creates a color average calculator that calculates averages with
    /// the given accuracy, algorithm, and alpha threshold.
    ///
    /// - Parameters:
    ///   - accuracy: The accuracy and performance of the calculator's
    ///     algorithm.
    ///   - algorithm: The algorithm used to calculate the average color
    ///     of the pixels in an image.
    ///   - alphaThreshold: Pixels with an alpha component that is below
    ///     this value are excluded from the average.
    init(
        accuracy: Accuracy,
        algorithm: Algorithm = .simple,
        alphaThreshold: CGFloat = 0.5
    ) {
        self.accuracy = accuracy
        self.algorithm = algorithm
        self.alphaThreshold = alphaThreshold
    }

    /// Calculates the average alpha, red, green, and blue color components
    /// for the given image.
    func calculateColorComponents(forImage image: CGImage) -> ColorComponents? {
        // resize the image based on the accuracy; smaller images remove
        // more pixels, decreasing accuracy, but increasing performance
        let size = computeSize(forImage: image)

        guard
            let context = createContext(withSize: size),
            let data = createImageData(forImage: image, context: context)
        else {
            return nil
        }

        let width = Int(size.width)
        let height = Int(size.height)

        // convert the alpha threshold to an integer multiplied by 255 to
        // match the component scale; pixels with an alpha component below
        // this value are excluded from the average
        let alphaThreshold = Int(alphaThreshold * 255)

        // define the summing operation outside the loop to avoid having
        // to repeatedly check which algorithm is being used
        let sumInPlace: (
            _ totals: inout (alpha: Int, red: Int, green: Int, blue: Int),
            _ a: UInt8, _ r: UInt8, _ g: UInt8, _ b: UInt8
        ) -> Void = {
            switch algorithm {
            case .simple:
                return { totals, a, r, g, b in
                    totals.alpha += Int(a)
                    totals.red += Int(r)
                    totals.green += Int(g)
                    totals.blue += Int(b)
                }
            case .squareRoot:
                return { totals, a, r, g, b in
                    totals.alpha += Int(pow(CGFloat(a), 2))
                    totals.red += Int(pow(CGFloat(r), 2))
                    totals.green += Int(pow(CGFloat(g), 2))
                    totals.blue += Int(pow(CGFloat(b), 2))
                }
            }
        }()

        // start with a full pixel count; if any pixels are skipped,
        // the count is decremented accordingly
        var pixelCount = width * height

        // start with the totals zero'd out
        var totals = (alpha: 0, red: 0, green: 0, blue: 0)

        for column in 0..<width {
            for row in 0..<height {
                let pixel = data[(row * width) + column]

                let alphaComponent = computeComponent(forPixel: pixel, shift: .alpha)
                guard alphaComponent >= alphaThreshold else {
                    pixelCount -= 1 // don't include this pixel
                    continue
                }

                // sum the alpha, red, green, and blue components
                sumInPlace(
                    &totals,
                    alphaComponent,
                    computeComponent(forPixel: pixel, shift: .red),
                    computeComponent(forPixel: pixel, shift: .green),
                    computeComponent(forPixel: pixel, shift: .blue)
                )
            }
        }

        // compute the averages of the summed components
        let averages: (alpha: CGFloat, red: CGFloat, green: CGFloat, blue: CGFloat) = {
            switch algorithm {
            case .simple:
                return (
                    alpha: CGFloat(totals.alpha) / CGFloat(pixelCount),
                    red: CGFloat(totals.red) / CGFloat(pixelCount),
                    green: CGFloat(totals.green) / CGFloat(pixelCount),
                    blue: CGFloat(totals.blue) / CGFloat(pixelCount)
                )
            case .squareRoot:
                return (
                    alpha: sqrt(CGFloat(totals.alpha) / CGFloat(pixelCount)),
                    red: sqrt(CGFloat(totals.red) / CGFloat(pixelCount)),
                    green: sqrt(CGFloat(totals.green) / CGFloat(pixelCount)),
                    blue: sqrt(CGFloat(totals.blue) / CGFloat(pixelCount))
                )
            }
        }()

        // divide each component by 255 to get the correct scale (0...1)
        return ColorComponents(
            red: averages.red / 255,
            green: averages.green / 255,
            blue: averages.blue / 255,
            alpha: averages.alpha / 255
        )
    }

    /// Computes a new size for the given image, based on the calculator's
    /// accuracy property.
    private func computeSize(forImage image: CGImage) -> CGSize {
        // get the image's maximum dimension, limited to 1000; use a lazy
        // var to avoid unnecessary allocation if the dimension isn't needed
        lazy var dimension = CGFloat(max(image.width, image.height, 1000))
        switch accuracy {
        case .low:
            // size should be no more than 10x10
            dimension /= 100
            return CGSize(width: dimension, height: dimension)
        case .medium:
            // size should be no more than 100x100
            dimension /= 10
            return CGSize(width: dimension, height: dimension)
        case .high:
            // size should be no more than 1000x1000
            return CGSize(width: dimension, height: dimension)
        case .exact:
            // ignore the maximum dimension and return the exact
            // size of the image
            return CGSize(width: image.width, height: image.height)
        }
    }

    /// Creates a bitmap context for resizing images according to the
    /// calculator's properties.
    private func createContext(withSize size: CGSize) -> CGContext? {
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

    /// Draws an image into the given context and returns the raw data.
    private func createImageData(
        forImage image: CGImage,
        context: CGContext
    ) -> UnsafeMutablePointer<UInt32>? {
        let rect = CGRect(x: 0, y: 0, width: context.width, height: context.height)
        context.draw(image, in: rect)
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
    private func computeComponent(forPixel pixel: UInt32, shift: Shift) -> UInt8 {
        UInt8((pixel >> shift.rawValue) & 255)
    }
}
