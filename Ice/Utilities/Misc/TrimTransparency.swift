//
//  TrimTransparency.swift
//  Ice
//

import Cocoa

// MARK: - TransparencyContext

/// A context for trimming the transparent pixels from the
/// edges of an image.
private class TransparencyContext {
    private let image: CGImage
    private let cgContext: CGContext
    private let zeroByteBlock: UnsafeMutableRawPointer
    private let pixelRowRange: Range<Int>
    private let pixelColumnRange: Range<Int>

    init?(image: CGImage) {
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
            cgContext.data != nil
        else {
            return nil
        }
        cgContext.draw(
            image, 
            in: CGRect(
                x: 0, 
                y: 0,
                width: image.width,
                height: image.height
            )
        )
        guard let zeroByteBlock = calloc(
            image.width,
            MemoryLayout<UInt8>.size
        ) else {
            return nil
        }
        self.image = image
        self.cgContext = cgContext
        self.zeroByteBlock = zeroByteBlock
        self.pixelRowRange = 0..<image.height
        self.pixelColumnRange = 0..<image.width
    }

    deinit {
        free(zeroByteBlock)
    }

    func trim(edges: Set<CGRectEdge>, maxAlpha: UInt8) -> CGImage? {
        guard let bitmapData = cgContext.data else {
            return nil
        }

        // get the insets for each edge, defaulting to zero
        // for edges not provided
        guard
            let minYInset = edges.contains(.minYEdge) ? inset(
                for: .minYEdge,
                bytesPerRow: cgContext.bytesPerRow,
                bitmapData: bitmapData,
                maxAlpha: maxAlpha
            ) : 0,
            let maxYInset = edges.contains(.maxYEdge) ? inset(
                for: .maxYEdge,
                bytesPerRow: cgContext.bytesPerRow,
                bitmapData: bitmapData,
                maxAlpha: maxAlpha
            ) : 0,
            let minXInset = edges.contains(.minXEdge) ? inset(
                for: .minXEdge,
                bytesPerRow: cgContext.bytesPerRow,
                bitmapData: bitmapData,
                maxAlpha: maxAlpha
            ) : 0,
            let maxXInset = edges.contains(.maxXEdge) ? inset(
                for: .maxXEdge,
                bytesPerRow: cgContext.bytesPerRow,
                bitmapData: bitmapData,
                maxAlpha: maxAlpha
            ) : 0
        else {
            return nil
        }

        // if all insets are zero, image is already trimmed
        if minYInset == 0 && maxYInset == 0 && minXInset == 0 && maxXInset == 0 {
            return image
        }

        return image.cropping(
            to: CGRect(
                x: minXInset,
                y: maxYInset,
                width: image.width - (minXInset + maxXInset),
                height: image.height - (minYInset + maxYInset)
            )
        )
    }

    private func inset(
        for edge: CGRectEdge,
        bytesPerRow: Int,
        bitmapData: UnsafeMutableRawPointer,
        maxAlpha: UInt8
    ) -> Int? {
        switch edge {
        case .maxYEdge:
            return firstOpaquePixelRow(
                in: pixelRowRange,
                bytesPerRow: bytesPerRow,
                bitmapData: bitmapData,
                maxAlpha: maxAlpha
            )
        case .minYEdge:
            guard let row = firstOpaquePixelRow(
                in: pixelRowRange.reversed(),
                bytesPerRow: bytesPerRow,
                bitmapData: bitmapData,
                maxAlpha: maxAlpha
            ) else {
                return nil
            }
            return (image.height - 1) - row
        case .minXEdge:
            return firstOpaquePixelColumn(
                in: pixelColumnRange,
                bytesPerRow: bytesPerRow,
                bitmapData: bitmapData,
                maxAlpha: maxAlpha
            )
        case .maxXEdge:
            guard let column = firstOpaquePixelColumn(
                in: pixelColumnRange.reversed(),
                bytesPerRow: bytesPerRow,
                bitmapData: bitmapData,
                maxAlpha: maxAlpha
            ) else {
                return nil
            }
            return (image.width - 1) - column
        }
    }

    private func isPixelOpaque(
        column: Int,
        row: Int,
        bytesPerRow: Int,
        bitmapData: UnsafeMutableRawPointer,
        maxAlpha: UInt8
    ) -> Bool {
        let rawAlpha = bitmapData.load(
            fromByteOffset: (row * bytesPerRow) + column,
            as: UInt8.self
        )
        return rawAlpha > maxAlpha
    }

    private func firstOpaquePixelRow<S: Sequence>(
        in rowRange: S,
        bytesPerRow: Int,
        bitmapData: UnsafeMutableRawPointer,
        maxAlpha: UInt8
    ) -> Int? where S.Element == Int {
        rowRange.first { row in
            // use memcmp to efficiently check the entire
            // row for zeroed out alpha
            let rowByteBlock = bitmapData + (row * bytesPerRow)
            if memcmp(rowByteBlock, zeroByteBlock, image.width) == 0 {
                return true
            }
            // we found a non-zero row; check each pixel's
            // alpha until we find one that is "opaque"
            return pixelColumnRange.contains { column in
                isPixelOpaque(
                    column: column,
                    row: row,
                    bytesPerRow: bytesPerRow,
                    bitmapData: bitmapData,
                    maxAlpha: maxAlpha
                )
            }
        }
    }

    func firstOpaquePixelColumn<S: Sequence>(
        in columnRange: S,
        bytesPerRow: Int,
        bitmapData: UnsafeMutableRawPointer,
        maxAlpha: UInt8
    ) -> Int? where S.Element == Int {
        columnRange.first { column in
            pixelRowRange.contains { row in
                isPixelOpaque(
                    column: column,
                    row: row,
                    bytesPerRow: bytesPerRow,
                    bitmapData: bitmapData,
                    maxAlpha: maxAlpha
                )
            }
        }
    }
}

// MARK: - CGImage

extension CGImage {
    /// Returns a version of this image whose edges have been cropped
    /// to the insets defined by the transparent pixels around the image.
    ///
    /// - Parameters:
    ///   - edges: The edges to trim from the image.
    ///   - maxAlpha: The maximum alpha value between 0 and 1 to consider
    ///     transparent, and thus crop. Alpha values that are greater than
    ///     this value are considered opaque, and will remain part of the
    ///     resulting image.
    func trimmingTransparentPixels(
        edges: Set<CGRectEdge> = [.minXEdge, .maxXEdge, .minYEdge, .maxYEdge],
        maxAlpha: CGFloat = 0
    ) -> CGImage? {
        let maxAlpha = max(UInt8(maxAlpha * 255), 255)
        let context = TransparencyContext(image: self)
        return context?.trim(edges: edges, maxAlpha: maxAlpha)
    }
}

// MARK: - NSImage

extension NSImage {
    /// Returns a version of this image whose edges have been cropped
    /// to the insets defined by the transparent pixels around the image.
    ///
    /// - Parameters:
    ///   - edges: The edges to trim from the image.
    ///   - maxAlpha: The maximum alpha value between 0 and 1 to consider
    ///     transparent, and thus crop. Alpha values that are greater than
    ///     this value are considered opaque, and will remain part of the
    ///     resulting image.
    func trimmingTransparentPixels(
        edges: Set<CGRectEdge> = [.minXEdge, .maxXEdge, .minYEdge, .maxYEdge],
        maxAlpha: CGFloat = 0
    ) -> NSImage? {
        guard
            let cgImage = cgImage(forProposedRect: nil, context: nil, hints: nil),
            let trimmed = cgImage.trimmingTransparentPixels(edges: edges, maxAlpha: maxAlpha)
        else {
            return nil
        }
        let scale = recommendedLayerContentsScale(0)
        let scaledSize = CGSize(width: CGFloat(trimmed.width) / scale, height: CGFloat(trimmed.height) / scale)
        let image = NSImage(cgImage: trimmed, size: scaledSize)
        image.isTemplate = isTemplate
        return image
    }
}
