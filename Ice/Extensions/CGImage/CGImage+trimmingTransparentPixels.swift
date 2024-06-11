//
//  CGImage+trimmingTransparentPixels.swift
//  Ice
//

import CoreGraphics

// MARK: - TransparencyContext

/// A context for handling transparency data in an image.
private class TransparencyContext {
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
            return image // nothing to trim
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
            return image // already trimmed
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
            // use memcmp to efficiently check the entire row for zeroed out alpha
            let rowByteBlock = bitmapData + (row * cgContext.bytesPerRow)
            if memcmp(rowByteBlock, zeroByteBlock, image.width) == 0 {
                return true
            }
            // we found a non-zero row; check each pixel's alpha until we find one
            // that is "opaque"
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

// MARK: - CGImage

extension CGImage {
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
