//
//  Extensions.swift
//  Ice
//

import AXSwift
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

    // MARK: Average Color

    /// Options that effect how colors are processed when computing
    /// an average color.
    struct ColorAverageOption: OptionSet {
        let rawValue: Int

        /// Includes the alpha component in the resulting average.
        static let ignoreAlpha = ColorAverageOption(rawValue: 1 << 0)
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
    func averageColor(using colorSpace: CGColorSpace? = nil, alphaThreshold: CGFloat = 0.5, option: ColorAverageOption = []) -> CGColor? {
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

    // MARK: Trim Transparent Pixels

    /// A context for handling transparency data in an image.
    private struct TransparencyContext: ~Copyable {
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

        private func isPixelOpaque(row: Int, column: Int) -> Bool {
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
                // We found a non-zero row. Check each pixel until we find one that is opaque.
                return columnRange.contains { column in
                    isPixelOpaque(row: row, column: column)
                }
            }
        }

        private func firstOpaqueColumn<S: Sequence>(in columnRange: S) -> Int? where S.Element == Int {
            columnRange.first { column in
                rowRange.contains { row in
                    isPixelOpaque(row: row, column: column)
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
        let maxAlpha = UInt8(maxAlpha.clamped(to: 0...1) * 255)
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
    /// tag appears in the collection.
    func firstIndex(matching tag: MenuBarItemTag) -> Index? {
        firstIndex { $0.tag == tag }
    }
}

// MARK: - Comparable

extension Comparable {
    /// Clamps this value to the given limiting range.
    ///
    /// - Parameter limits: A range of values to clamp this value to.
    mutating func clamp(to limits: ClosedRange<Self>) {
        self = min(max(self, limits.lowerBound), limits.upperBound)
    }

    /// Returns a copy of this value, clamped to the given limiting
    /// range.
    ///
    /// - Parameter limits: A range of values to clamp the copy to.
    func clamped(to limits: ClosedRange<Self>) -> Self {
        withMutableCopy(of: self) { $0.clamp(to: limits) }
    }
}

// MARK: - DistributedNotificationCenter

extension DistributedNotificationCenter {
    /// A notification posted whenever the system-wide interface theme changes.
    static let interfaceThemeChangedNotification = Notification.Name("AppleInterfaceThemeChangedNotification")
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
        let menuBarWindow = WindowInfo.menuBarWindow(for: displayID)
        return menuBarWindow?.bounds.height
    }

    /// Returns the frame of the application menu on this screen.
    func getApplicationMenuFrame() -> CGRect? {
        let displayBounds = CGDisplayBounds(displayID)

        guard
            let menuBar = try? systemWideElement.elementAtPosition(displayBounds.origin),
            let role = try? menuBar.role(),
            role == .menuBar
        else {
            return nil
        }

        let applicationMenuFrame = menuBar.children.reduce(CGRect.null) { result, child in
            guard child.isEnabled, let childFrame = child.frame else {
                return result
            }
            return result.union(childFrame)
        }

        if applicationMenuFrame.width <= 0 {
            return nil
        }

        // The Accessibility API returns the menu bar for the active screen, regardless of the
        // display origin used. This workaround prevents an incorrect frame from being returned
        // for inactive displays in multi-display setups where one display has a notch.
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
    /// Replaces all elements from the upstream publisher using the
    /// provided closure.
    ///
    /// - Parameter transform: A closure that returns an element to
    ///   publish in place of the upstream element.
    func replace<T>(_ transform: @escaping () -> T) -> Publishers.Map<Self, T> {
        map { _ in transform() }
    }

    /// Replaces all elements from the upstream publisher with the
    /// provided element.
    ///
    /// - Parameter output: An element to publish in place of the
    ///   upstream element.
    func replace<T>(with output: T) -> Publishers.Map<Self, T> {
        replace { output }
    }

    func removeNil<T>() -> Publishers.CompactMap<Self, T> where Output == T? {
        compactMap { $0 }
    }

    func mergeReplace<P: Publisher, T>(_ other: P, with output: T) -> Publishers.Merge<Publishers.Map<Self, T>, Publishers.Map<P, T>> {
        replace(with: output).merge(with: other.replace(with: output))
    }

    func mergeReplace<P: Publisher, T>(_ other: P, transform: @escaping () -> T) -> Publishers.Merge<Publishers.Map<Self, T>, Publishers.Map<P, T>> {
        replace(transform).merge(with: other.replace(transform))
    }

    func discardMerge<P: Publisher>(_ other: P) -> Publishers.Merge<Publishers.Map<Self, Void>, Publishers.Map<P, Void>> {
        mergeReplace(other, with: ())
    }

    func removeDuplicates<each T: Equatable>() -> Publishers.RemoveDuplicates<Self> where Output == (repeat each T) {
        removeDuplicates { lhs, rhs in
            for (left, right) in repeat (each lhs, each rhs) {
                guard left == right else { return false }
            }
            return true
        }
    }
}

extension Publisher {
    func publisher<Value>(
        for keyPath: KeyPath<Output, Value>,
        options: NSKeyValueObservingOptions = [.initial, .new]
    ) -> some Publisher<Value, Failure> where Output: NSObject {
        flatMap { $0.publisher(for: keyPath, options: options) }
    }

    func publisher<Wrapped: NSObject, Value>(
        for keyPath: KeyPath<Wrapped, Value>,
        options: NSKeyValueObservingOptions = [.initial, .new]
    ) -> some Publisher<Value?, Failure> where Output == Wrapped? {
        flatMap { $0.publisher }
            .flatMap { $0.publisher(for: keyPath, options: options) }
            .map { $0 as Value? }
            .replaceEmpty(with: nil)
    }

    func publisher<Wrapped: NSObject, Value>(
        for keyPath: KeyPath<Wrapped, Value?>,
        options: NSKeyValueObservingOptions = [.initial, .new]
    ) -> some Publisher<Value?, Failure> where Output == Wrapped? {
        flatMap { $0.publisher }
            .flatMap { $0.publisher(for: keyPath, options: options) }
            .replaceEmpty(with: nil)
    }
}

// MARK: - Publisher where Output: Sequence, Failure == Never

extension Publisher where Output: Sequence, Failure == Never {
    /// Transforms the elements of the upstream sequence into publishers and
    /// merges the results.
    ///
    /// - Parameter transform: A closure that takes an element of the upstream
    ///   sequence as a parameter and returns a publisher.
    ///
    /// - Returns: A publisher that emits an event when any upstream publisher
    ///   emits an event.
    func mergeMap<P: Publisher>(_ transform: @escaping (Output.Element) -> P) -> some Publisher<P.Output, P.Failure> {
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

    /// Removes duplicate values from the collection.
    mutating func removeDuplicates() {
        self = self.removingDuplicates()
    }
}

// MARK: - RangeReplaceableCollection where Element == MenuBarItem

extension RangeReplaceableCollection where Element == MenuBarItem {
    /// Removes and returns the first menu bar item that matches the
    /// specified tag.
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

// MARK: - SystemWideElement

extension SystemWideElement {
    /// Returns the element at the specified top-down coordinates.
    func elementAtPosition(_ point: CGPoint) throws -> UIElement? {
        try elementAtPosition(Float(point.x), Float(point.y))
    }
}

// MARK: - UIElement

extension UIElement {
    /// The element's child elements.
    var children: [UIElement] {
        (try? arrayAttribute(.children)) ?? []
    }

    /// The element's frame.
    var frame: CGRect? {
        try? attribute(.frame)
    }

    /// A Boolean value that indicates whether the element is enabled.
    var isEnabled: Bool {
        (try? attribute(.enabled)) == true
    }
}
