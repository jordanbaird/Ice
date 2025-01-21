//
//  Extensions.swift
//  Ice
//

import Combine
import SwiftUI

// MARK: - Bundle

extension Bundle {
    /// The bundle's copyright string.
    ///
    /// This accessor looks for an associated value for the "NSHumanReadableCopyright"
    /// key in the bundle's Info.plist. If a string value cannot be found for this key,
    /// this accessor returns `nil`.
    var copyrightString: String? {
        object(forInfoDictionaryKey: "NSHumanReadableCopyright") as? String
    }

    /// The bundle's version string.
    ///
    /// This accessor looks for an associated value for either "CFBundleShortVersionString"
    /// or "CFBundleVersion" in the bundle's Info.plist. If a string value cannot be found
    /// for one of these keys, this accessor returns `nil`.
    var versionString: String? {
        object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ??
        object(forInfoDictionaryKey: "CFBundleVersion") as? String
    }
}

// MARK: - CGColor

extension CGColor {
    /// The brightness of the color.
    var brightness: CGFloat? {
        guard
            let rgb = converted(to: CGColorSpaceCreateDeviceRGB(), intent: .defaultIntent, options: nil),
            let components = rgb.components
        else {
            return nil
        }
        // Algorithm from http://www.w3.org/WAI/ER/WD-AERT/#color-contrast
        return ((components[0] * 299) + (components[1] * 587) + (components[2] * 114)) / 1000
    }
}

// MARK: - CGError

extension CGError {
    /// A string to use for logging purposes.
    var logString: String {
        switch self {
        case .success: "\(rawValue): success"
        case .failure: "\(rawValue): failure"
        case .illegalArgument: "\(rawValue): illegalArgument"
        case .invalidConnection: "\(rawValue): invalidConnection"
        case .invalidContext: "\(rawValue): invalidContext"
        case .cannotComplete: "\(rawValue): cannotComplete"
        case .notImplemented: "\(rawValue): notImplemented"
        case .rangeCheck: "\(rawValue): rangeCheck"
        case .typeCheck: "\(rawValue): typeCheck"
        case .invalidOperation: "\(rawValue): invalidOperation"
        case .noneAvailable: "\(rawValue): noneAvailable"
        @unknown default: "\(rawValue): unknown"
        }
    }
}

// MARK: - CGImage

extension CGImage {
    /// Constants that determine the resolution of a color averaging algorithm.
    enum ColorAverageResolution {
        /// Low resolution, reducing accuracy, but increasing performance.
        case low
        /// Medium resolution, with nominal accuracy and performance.
        case medium
        /// High resolution, increasing accuracy, but reducing performance.
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
        // Resize the image based on the resolution. Smaller images remove more pixels,
        // decreasing accuracy, but increasing performance.
        let size = switch resolution {
        case .low:
            CGSize(width: min(width, 10), height: min(height, 10))
        case .medium:
            CGSize(width: min(width, 50), height: min(height, 50))
        case .high:
            CGSize(width: min(width, 100), height: min(height, 100))
        }

        guard
            let context = createContext(size: size),
            let data = createImageData(context: context)
        else {
            return nil
        }

        let width = Int(size.width)
        let height = Int(size.height)

        // Convert the alpha threshold to an integer, multiplied by 255. Pixels with
        // an alpha component below this value are excluded from the average.
        let alphaThreshold = Int(alphaThreshold * 255)

        // Start with a full pixel count. If any pixels are skipped, the count is
        // decremented accordingly.
        var pixelCount = width * height

        // Start with the totals zeroed out.
        var totalRed = 0
        var totalGreen = 0
        var totalBlue = 0
        var totalAlpha = 0

        for column in 0..<width {
            for row in 0..<height {
                let pixel = data[(row * width) + column]

                // Check alpha before computing other components.
                let alphaComponent = computeComponentValue(.alpha, for: pixel)

                guard alphaComponent >= alphaThreshold else {
                    pixelCount -= 1 // Don't include this pixel.
                    continue
                }

                let redComponent = computeComponentValue(.red, for: pixel)
                let greenComponent = computeComponentValue(.green, for: pixel)
                let blueComponent = computeComponentValue(.blue, for: pixel)

                // Sum the red, green, blue, and alpha components.
                totalRed += redComponent
                totalGreen += greenComponent
                totalBlue += blueComponent
                totalAlpha += alphaComponent
            }
        }

        // Compute the averages of the summed components.
        let averageRed = CGFloat(totalRed) / CGFloat(pixelCount)
        let averageGreen = CGFloat(totalGreen) / CGFloat(pixelCount)
        let averageBlue = CGFloat(totalBlue) / CGFloat(pixelCount)
        let averageAlpha = CGFloat(totalAlpha) / CGFloat(pixelCount)

        // Divide each component by 255 to convert to floating point.
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
        return Int((pixel >> component.rawValue) & 255)
    }
}

// MARK: - CGImage

extension CGImage {
    /// A context for handling transparency data in an image.
    private final class TransparencyContext {
        private let image: CGImage
        private let maxAlpha: UInt8
        private let cgContext: CGContext
        private let zeroByteBlock: UnsafeMutableRawPointer
        private let rowRange: LazySequence<Range<Int>>
        private let columnRange: LazySequence<Range<Int>>

        /// Creates a context with the given image and alpha threshold.
        ///
        /// - Parameters:
        ///   - image: The image to form a context around.
        ///   - maxAlpha: The maximum alpha value to consider transparent.
        init?(image: CGImage, maxAlpha: UInt8) {
            guard
                let cgContext = CGContext(
                    data: nil,
                    width: image.width,
                    height: image.height,
                    bitsPerComponent: 8,
                    bytesPerRow: 0,
                    space: CGColorSpaceCreateDeviceGray(),
                    bitmapInfo: CGImageAlphaInfo.alphaOnly.rawValue
                ),
                cgContext.data != nil,
                let zeroByteBlock = calloc(image.width, MemoryLayout<UInt8>.size)
            else {
                return nil
            }

            cgContext.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))

            self.image = image
            self.maxAlpha = maxAlpha
            self.cgContext = cgContext
            self.zeroByteBlock = zeroByteBlock
            self.rowRange = (0..<image.height).lazy
            self.columnRange = (0..<image.width).lazy
        }

        deinit {
            free(zeroByteBlock)
        }

        /// Trims transparent pixels from the context.
        func trim(edges: Set<CGRectEdge>) -> CGImage? {
            guard
                maxAlpha < 255,
                !edges.isEmpty
            else {
                return image // Nothing to trim.
            }

            guard
                let minYInset = inset(for: .minYEdge, in: edges),
                let maxYInset = inset(for: .maxYEdge, in: edges),
                let minXInset = inset(for: .minXEdge, in: edges),
                let maxXInset = inset(for: .maxXEdge, in: edges)
            else {
                return nil
            }

            guard (minYInset, maxYInset, minXInset, maxXInset) != (0, 0, 0, 0) else {
                return image // Already trimmed.
            }

            let insetRect = CGRect(
                x: minXInset,
                y: maxYInset,
                width: image.width - (minXInset + maxXInset),
                height: image.height - (minYInset + maxYInset)
            )

            return image.cropping(to: insetRect)
        }

        private func inset(for edge: CGRectEdge, in edges: Set<CGRectEdge>) -> Int? {
            guard edges.contains(edge) else {
                return 0
            }
            return switch edge {
            case .maxYEdge:
                firstOpaqueRow(in: rowRange)
            case .minYEdge:
                firstOpaqueRow(in: rowRange.reversed()).map { (image.height - 1) - $0 }
            case .minXEdge:
                firstOpaqueColumn(in: columnRange)
            case .maxXEdge:
                firstOpaqueColumn(in: columnRange.reversed()).map { (image.width - 1) - $0 }
            }
        }

        private func isPixelOpaque(column: Int, row: Int) -> Bool {
            guard let bitmapData = cgContext.data else {
                return false
            }
            let rawAlpha = bitmapData.load(fromByteOffset: (row * cgContext.bytesPerRow) + column, as: UInt8.self)
            return rawAlpha > maxAlpha
        }

        private func firstOpaqueRow<S: Sequence>(in rowRange: S) -> Int? where S.Element == Int {
            guard let bitmapData = cgContext.data else {
                return nil
            }
            return rowRange.first { row in
                // Use memcmp to efficiently check the entire row for zeroed out alpha.
                let rowByteBlock = bitmapData + (row * cgContext.bytesPerRow)
                if memcmp(rowByteBlock, zeroByteBlock, image.width) == 0 {
                    return true
                }
                // We found a non-zero row. Check each pixel's alpha until we find one
                // that is "opaque".
                return columnRange.contains { column in
                    isPixelOpaque(column: column, row: row)
                }
            }
        }

        private func firstOpaqueColumn<S: Sequence>(in columnRange: S) -> Int? where S.Element == Int {
            columnRange.first { column in
                rowRange.contains { row in
                    isPixelOpaque(column: column, row: row)
                }
            }
        }
    }

    /// Returns an image that has been trimmed of transparency around the given edges.
    ///
    /// - Parameters:
    ///   - edges: The edges to trim from around the image.
    ///   - maxAlpha: The maximum alpha value to consider transparent. Pixels with alpha
    ///     values above this value will be considered opaque, and will therefore remain
    ///     in the image.
    func trimmingTransparentPixels(
        around edges: Set<CGRectEdge> = [.minXEdge, .maxXEdge, .minYEdge, .maxYEdge],
        maxAlpha: CGFloat = 0
    ) -> CGImage? {
        let maxAlpha = min(UInt8(maxAlpha * 255), 255)
        let context = TransparencyContext(image: self, maxAlpha: maxAlpha)
        return context?.trim(edges: edges)
    }

    /// Returns a Boolean value that indicates whether the image is transparent.
    ///
    /// - Parameter maxAlpha: The maximum alpha value to consider transparent.
    ///   Pixels with alpha values above this value will be considered opaque.
    func isTransparent(maxAlpha: CGFloat = 0) -> Bool {
        // FIXME: This needs a dedicated implementation instead of relying on `trimmingTransparentPixels`
        trimmingTransparentPixels(maxAlpha: maxAlpha) == nil
    }
}

// MARK: - Collection where Element == MenuBarItem

extension Collection where Element == MenuBarItem {
    /// Returns the first index where the menu bar item matching the specified
    /// info appears in the collection.
    func firstIndex(matching info: MenuBarItemInfo) -> Index? {
        firstIndex { $0.info == info }
    }
}

// MARK: - Comparable

extension Comparable {
    /// Returns a copy of this value that has been clamped within the bounds
    /// of the given limiting range.
    ///
    /// - Parameter limits: A closed range within which to clamp this value.
    func clamped(to limits: ClosedRange<Self>) -> Self {
        min(max(self, limits.lowerBound), limits.upperBound)
    }
}

// MARK: - EdgeInsets

extension EdgeInsets {
    /// Creates edge insets with the given floating point value.
    init(all: CGFloat) {
        self.init(top: all, leading: all, bottom: all, trailing: all)
    }
}

// MARK: - NSApplication

extension NSApplication {
    /// Returns the window with the given identifier.
    func window(withIdentifier identifier: String) -> NSWindow? {
        windows.first { $0.identifier?.rawValue == identifier }
    }
}

// MARK: - NSBezierPath

extension NSBezierPath {
    /// Draws a shadow in the shape of the path.
    ///
    /// - Parameters:
    ///   - color: The color of the drawn shadow.
    ///   - radius: The radius of the drawn shadow.
    func drawShadow(color: NSColor, radius: CGFloat) {
        guard let context = NSGraphicsContext.current else {
            return
        }

        let bounds = bounds.insetBy(dx: -radius, dy: -radius)

        let shadow = NSShadow()
        shadow.shadowBlurRadius = radius
        shadow.shadowColor = color

        // swiftlint:disable:next force_cast
        let path = copy() as! NSBezierPath

        context.saveGraphicsState()

        shadow.set()
        NSColor.black.set()
        bounds.clip()
        path.fill()

        context.restoreGraphicsState()
    }

    /// Returns a new path filled with regions in either this path or the
    /// given path.
    ///
    /// - Parameters:
    ///   - other: A path to union with this path.
    ///   - windingRule: The winding rule used to join the paths.
    func union(_ other: NSBezierPath, using windingRule: WindingRule = .evenOdd) -> NSBezierPath {
        let fillRule: CGPathFillRule = switch windingRule {
        case .nonZero: .winding
        case .evenOdd: .evenOdd
        @unknown default: fatalError("Unknown winding rule \(windingRule)")
        }
        return NSBezierPath(cgPath: cgPath.union(other.cgPath, using: fillRule))
    }
}

// MARK: - NSImage

extension NSImage {
    /// Returns a new image that has been resized to the given size.
    ///
    /// - Note: This method retains the ``isTemplate`` property.
    ///
    /// - Parameter size: The size to resize the current image to.
    func resized(to size: CGSize) -> NSImage {
        let resizedImage = NSImage(size: size, flipped: false) { bounds in
            self.draw(in: bounds)
            return true
        }
        resizedImage.isTemplate = isTemplate
        return resizedImage
    }
}

// MARK: - NSScreen

extension NSScreen {
    /// The screen containing the mouse pointer.
    static var screenWithMouse: NSScreen? {
        screens.first { $0.frame.contains(NSEvent.mouseLocation) }
    }

    /// The display identifier of the screen.
    var displayID: CGDirectDisplayID {
        // Value and type are guaranteed here, so force casting is okay.
        // swiftlint:disable:next force_cast
        deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as! CGDirectDisplayID
    }

    /// A Boolean value that indicates whether the screen has a notch.
    var hasNotch: Bool {
        safeAreaInsets.top != 0
    }

    /// The frame of the screen's notch, if it has one.
    var frameOfNotch: CGRect? {
        guard
            let auxiliaryTopLeftArea,
            let auxiliaryTopRightArea
        else {
            return nil
        }
        return CGRect(
            x: auxiliaryTopLeftArea.maxX,
            y: frame.maxY - safeAreaInsets.top,
            width: auxiliaryTopRightArea.minX - auxiliaryTopLeftArea.maxX,
            height: safeAreaInsets.top
        )
    }

    /// Returns the height of the menu bar on this screen.
    func getMenuBarHeight() -> CGFloat? {
        let menuBarWindow = WindowInfo.getMenuBarWindow(for: displayID)
        return menuBarWindow?.frame.height
    }
}

// MARK: - NSStatusItem

extension NSStatusItem {
    /// Shows the given menu under the status item.
    func showMenu(_ menu: NSMenu) {
        let originalMenu = self.menu
        defer {
            self.menu = originalMenu
        }
        self.menu = menu
        button?.performClick(nil)
    }
}

// MARK: - Publisher

extension Publisher {
    /// Transforms all elements from the upstream publisher into `Void` values.
    func mapToVoid() -> some Publisher<Void, Failure> {
        map { _ in () }
    }
}

// MARK: - Sequence where Element == MenuBarItem

extension Sequence where Element == MenuBarItem {
    /// Returns the menu bar items, sorted by their order in the menu bar.
    func sortedByOrderInMenuBar() -> [MenuBarItem] {
        sorted { lhs, rhs in
            lhs.frame.maxX < rhs.frame.maxX
        }
    }
}
