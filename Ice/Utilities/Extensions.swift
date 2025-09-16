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
    /// This accessor checks the bundle's `Info.plist` for a string value associated
    /// with the "NSHumanReadableCopyright" key. If a valid value cannot be found for
    /// the key, this accessor returns `nil`.
    var copyrightString: String? {
        object(forInfoDictionaryKey: "NSHumanReadableCopyright") as? String
    }

    /// The bundle's display name.
    ///
    /// This accessor checks the bundle's `Info.plist` for a string value associated
    /// with the "CFBundleDisplayName" key. If a valid value cannot be found for the
    /// key, the same check is performed for the "CFBundleName" key. If a valid value
    /// cannot be found for either key, this accessor returns `nil`.
    var displayName: String? {
        object(forInfoDictionaryKey: "CFBundleDisplayName") as? String ??
        object(forInfoDictionaryKey: "CFBundleName") as? String
    }

    /// The bundle's version string.
    ///
    /// This accessor checks the bundle's `Info.plist` for a string value associated
    /// with the "CFBundleShortVersionString" key. If a valid value cannot be found
    /// for the key, this accessor returns `nil`.
    var versionString: String? {
        object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String
    }

    /// The bundle's build string.
    ///
    /// This accessor checks the bundle's `Info.plist` for a string value associated
    /// with the "CFBundleVersion" key. If a valid value cannot be found for the key,
    /// this accessor returns `nil`.
    var buildString: String? {
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

// MARK: - CGImage

extension CGImage {

    // MARK: Color Averaging

    /// Options that effect how colors are processed when computing
    /// an average color.
    struct ColorAveragingOption: OptionSet {
        let rawValue: Int

        /// Includes the alpha component in the resulting average.
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
                bitmapInfo: CGBitmapInfo(alpha: .premultipliedFirst, byteOrder: .order32Little)
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
        let alphaThreshold = UInt64((alphaThreshold.clamped(to: 0...1) * 255).rounded(.toNearestOrAwayFromZero))

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

    // MARK: Transparency Trimming

    /// A context for handling transparency data in an image.
    private struct TransparencyContext: ~Copyable {
        private let image: CGImage
        private let alphaThreshold: CGFloat
        private let cgContext: CGContext
        private let data: UnsafeMutableRawPointer
        private let zeroByteBlock: UnsafeMutableRawPointer
        private let rowRange: Range<Int>
        private let columnRange: Range<Int>

        /// Creates a context with the given image and alpha threshold.
        ///
        /// - Parameters:
        ///   - image: The image to form a context around.
        ///   - alphaThreshold: The maximum alpha value to consider transparent.
        init?(image: CGImage, alphaThreshold: CGFloat) {
            guard
                image.width > 0,
                image.height > 0,
                alphaThreshold < 1,
                let cgContext = CGContext(
                    data: nil,
                    width: image.width,
                    height: image.height,
                    bitsPerComponent: 8,
                    bytesPerRow: 0,
                    space: CGColorSpaceCreateDeviceGray(),
                    bitmapInfo: CGBitmapInfo(alpha: .alphaOnly)
                ),
                let data = cgContext.data,
                let zeroByteBlock = calloc(image.width, MemoryLayout<UInt8>.size)
            else {
                return nil
            }

            let size = CGSize(width: image.width, height: image.height)
            cgContext.draw(image, in: CGRect(origin: .zero, size: size))

            self.image = image
            self.alphaThreshold = alphaThreshold
            self.cgContext = cgContext
            self.data = data
            self.zeroByteBlock = zeroByteBlock
            self.rowRange = 0..<image.height
            self.columnRange = 0..<image.width
        }

        deinit {
            free(zeroByteBlock)
        }

        /// Returns an image derived from the context's image that has been
        /// trimmed of transparency around the given edges.
        func trim(around edges: Set<CGRectEdge>) -> CGImage? {
            guard !edges.isEmpty else {
                return image // Nothing to trim.
            }

            guard
                let minXInset = inset(for: .minXEdge, in: edges),
                let minYInset = inset(for: .minYEdge, in: edges),
                let maxXInset = inset(for: .maxXEdge, in: edges),
                let maxYInset = inset(for: .maxYEdge, in: edges)
            else {
                return nil
            }

            guard (minXInset, minYInset, maxXInset, maxYInset) != (0, 0, 0, 0) else {
                return image // Already trimmed.
            }

            let insetRect = CGRect(
                x: minXInset,
                y: minYInset,
                width: max(image.width - (minXInset + maxXInset), 0),
                height: max(image.height - (minYInset + maxYInset), 0)
            )

            return image.cropping(to: insetRect)
        }

        /// Returns a Boolean value that indicates whether the context's
        /// image is transparent.
        func isTransparent() -> Bool {
            rowRange.allSatisfy { row in
                isRowTransparent(row: row)
            }
        }

        private func inset(for edge: CGRectEdge, in edges: Set<CGRectEdge>) -> Int? {
            guard edges.contains(edge) else {
                return 0
            }
            return switch edge {
            case .minXEdge:
                firstOpaqueColumn(in: columnRange)
            case .minYEdge:
                firstOpaqueRow(in: rowRange)
            case .maxXEdge:
                firstOpaqueColumn(in: columnRange.reversed()).map { (image.width - 1) - $0 }
            case .maxYEdge:
                firstOpaqueRow(in: rowRange.reversed()).map { (image.height - 1) - $0 }
            }
        }

        private func isPixelOpaque(row: Int, column: Int) -> Bool {
            let rawAlpha = data.load(
                fromByteOffset: (row * cgContext.bytesPerRow) + column,
                as: UInt8.self
            )
            let convertedAlpha = CGFloat(rawAlpha) / 255
            return convertedAlpha > alphaThreshold
        }

        private func isRowTransparent(row: Int) -> Bool {
            // Use memcmp to efficiently check the entire row for zeroed out alpha.
            if memcmp(data + (row * cgContext.bytesPerRow), zeroByteBlock, image.width) == 0 {
                return true
            }
            // Avoid checking individual pixels if we can.
            if alphaThreshold == 0 {
                return false
            }
            // Check each pixel in the row until we find one that is opaque.
            return !columnRange.contains { column in
                isPixelOpaque(row: row, column: column)
            }
        }

        private func firstOpaqueRow(in rowRange: some Sequence<Int>) -> Int? {
            rowRange.first { row in
                !isRowTransparent(row: row)
            }
        }

        private func firstOpaqueColumn(in columnRange: some Sequence<Int>) -> Int? {
            columnRange.first { column in
                rowRange.contains { row in
                    isPixelOpaque(row: row, column: column)
                }
            }
        }
    }

    /// Returns an image that has been trimmed of transparency around the
    /// given edges.
    ///
    /// Each edge is trimmed up to the first row or column containing pixels
    /// with an alpha component above the specified threshold.
    ///
    /// - Parameters:
    ///   - edges: A set of edges to trim from around the image.
    ///   - alphaThreshold: The maximum alpha value to consider transparent.
    func trimmingTransparency(
        around edges: Set<CGRectEdge> = [.minXEdge, .minYEdge, .maxXEdge, .maxYEdge],
        alphaThreshold: CGFloat = 0
    ) -> CGImage? {
        guard let context = TransparencyContext(image: self, alphaThreshold: alphaThreshold) else {
            return self
        }
        return context.trim(around: edges)
    }

    /// Returns a Boolean value that indicates whether the image is transparent.
    ///
    /// - Parameter alphaThreshold: The maximum alpha value to consider transparent.
    func isTransparent(alphaThreshold: CGFloat = 0) -> Bool {
        guard let context = TransparencyContext(image: self, alphaThreshold: alphaThreshold) else {
            return false
        }
        return context.isTransparent()
    }
}

// MARK: - Collection where Element == MenuBarItem

extension Collection where Element == MenuBarItem {
    /// Returns the first index where the menu bar item matching the specified
    /// tag appears in the collection.
    func firstIndex(matching tag: MenuBarItemTag) -> Index? {
        firstIndex { $0.tag == tag }
    }
}

// MARK: - Comparable

extension Comparable {
    /// Returns a copy of this value, clamped to the given minimum
    /// and maximum limiting values.
    ///
    /// - Parameters:
    ///   - min: The minimum limiting value.
    ///   - max: The maximum limiting value.
    ///
    /// - Precondition: `min <= max`
    ///
    /// - Returns: The value nearest this value that is both greater
    ///   than or equal to `min` and less than or equal to `max`.
    func clamped(min: Self, max: Self) -> Self {
        precondition(min <= max, "Clamp requires min <= max")
        return Swift.min(Swift.max(self, min), max)
    }

    /// Returns a copy of this value, clamped to the given limiting
    /// range.
    ///
    /// - Parameter range: A range of values of this type, whose
    ///   lower and upper bounds represent the minimum and maximum
    ///   limiting values.
    ///
    /// - Returns: The value nearest this value that is both greater
    ///   than or equal to `range.lowerBound` and less than or equal
    ///   to `range.upperBound`.
    func clamped(to range: ClosedRange<Self>) -> Self {
        clamped(min: range.lowerBound, max: range.upperBound)
    }
}

// MARK: - DistributedNotificationCenter

extension DistributedNotificationCenter {
    /// A notification posted whenever the system-wide interface theme changes.
    static let interfaceThemeChangedNotification = Notification.Name("AppleInterfaceThemeChangedNotification")
}

// MARK: - EdgeInsets

extension EdgeInsets {
    /// A copy of this instance with only the leading and trailing
    /// edges set.
    var horizontal: EdgeInsets {
        EdgeInsets(top: 0, leading: leading, bottom: 0, trailing: trailing)
    }

    /// A copy of this instance with only the top and bottom
    /// edges set.
    var vertical: EdgeInsets {
        EdgeInsets(top: top, leading: 0, bottom: bottom, trailing: 0)
    }

    /// Creates an instance with all edges set to the given value.
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

    /// The screen with the active menu bar.
    static var screenWithActiveMenuBar: NSScreen? {
        guard let displayID = Bridging.getActiveMenuBarDisplayID() else {
            return nil
        }
        return screens.first { $0.displayID == displayID }
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
        let menuBarWindow = WindowInfo.menuBarWindow(for: displayID)
        return menuBarWindow?.bounds.height
    }

    /// Returns the frame of the application menu on this screen.
    func getApplicationMenuFrame() -> CGRect? {
        let displayBounds = CGDisplayBounds(displayID)

        guard
            let menuBar = AXHelpers.element(at: displayBounds.origin),
            AXHelpers.role(for: menuBar) == .menuBar
        else {
            return nil
        }

        let applicationMenuFrame = AXHelpers.children(for: menuBar).reduce(into: CGRect.null) { result, child in
            if AXHelpers.isEnabled(child), let childFrame = AXHelpers.frame(for: child) {
                result = result.union(childFrame)
            }
        }

        if applicationMenuFrame.width <= 0 || applicationMenuFrame.isNull {
            return nil
        }

        // FIXME: The Accessibility API always returns the menu bar for the main screen.
        // This can cause issues if one of the screens has a notch, since long app menus
        // can display items the trailing side of the notch. This causes the frame to be
        // invalid for all other screens. For now, we're working around this by checking
        // the app menu's frame on inactive screens, and returning `nil` if it overlaps
        // with the notch.
        if
            let mainScreen = NSScreen.main,
            self != mainScreen,
            let notchedScreen = NSScreen.screens.first(where: { $0.hasNotch }),
            let leftArea = notchedScreen.auxiliaryTopLeftArea,
            applicationMenuFrame.width >= leftArea.maxX
        {
            return nil
        }

        return applicationMenuFrame
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
    /// Replaces each upstream element with an element returned from
    /// the given closure.
    ///
    /// - Parameter output: A closure that returns a new element to
    ///   publish in place of the upstream element.
    func replace<T>(_ output: @escaping () -> T) -> Publishers.Map<Self, T> {
        map { _ in output() }
    }

    /// Replaces each upstream element with the given element.
    ///
    /// - Parameter output: A new element to publish in place of the
    ///   upstream elements.
    func replace<T>(with output: T) -> Publishers.Map<Self, T> {
        replace { output }
    }

    /// Publishes only non-`nil` elements.
    func removeNil<T>() -> Publishers.CompactMap<Self, T> where Output == T? {
        compactMap { $0 }
    }

    /// Publishes only elements that don't match the previous element.
    func removeDuplicates<each T: Equatable>() -> Publishers.RemoveDuplicates<Self> where Output == (repeat each T) {
        removeDuplicates { lhs, rhs in
            for (left, right) in repeat (each lhs, each rhs) {
                guard left == right else { return false }
            }
            return true
        }
    }

    /// Merges this publisher with the given publisher, replacing upstream
    /// elements with `Void` values.
    ///
    /// - Parameter other: Another publisher.
    func discardMerge<P: Publisher>(_ other: P) -> some Publisher<Void, Failure> where P.Failure == Failure {
        replace(with: ()).merge(with: other.replace(with: ()))
    }

    /// Transforms the elements of the upstream sequence into a sequence of
    /// publishers and merges the results.
    ///
    /// - Parameter transform: A closure that takes an element of the upstream
    ///   sequence as a parameter and returns a publisher.
    ///
    /// - Returns: A publisher that emits an event when any upstream publisher
    ///   emits an event.
    func mergeMap<P: Publisher>(
        _ transform: @escaping (Output.Element) -> P
    ) -> some Publisher<P.Output, P.Failure> where Output: Sequence, Failure == Never {
        flatMap { sequence in
            Publishers.MergeMany(sequence.map(transform))
        }
    }
}

// MARK: - RangeReplaceableCollection where Element: Hashable

extension RangeReplaceableCollection where Element: Hashable {
    /// Returns a copy of the collection with duplicate values removed.
    func removingDuplicates() -> Self {
        var seen = Set<Element>()
        return filter { seen.insert($0).inserted }
    }
}

// MARK: - RangeReplaceableCollection where Element == MenuBarItem

extension RangeReplaceableCollection where Element == MenuBarItem {
    /// Removes and returns the first menu bar item that matches
    /// the specified tag.
    mutating func removeFirst(matching tag: MenuBarItemTag) -> MenuBarItem? {
        guard let index = firstIndex(matching: tag) else {
            return nil
        }
        return remove(at: index)
    }
}

// MARK: - Sequence where Element == MenuBarItem

extension Sequence where Element == MenuBarItem {
    /// Returns the first menu bar item that matches the specified tag.
    func first(matching tag: MenuBarItemTag) -> MenuBarItem? {
        first { $0.tag == tag }
    }
}
