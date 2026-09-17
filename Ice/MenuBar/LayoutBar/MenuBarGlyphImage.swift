//
//  MenuBarGlyphImage.swift
//  Ice
//

import CoreGraphics
import Foundation

/// Converts a captured status glyph into a transparent Layout asset. The
/// capture is input data, not a rectangle of menu-bar material to display.
enum MenuBarGlyphImage {
    struct Result {
        let image: CGImage
        let isTemplate: Bool
    }

    static func make(from image: CGImage) -> Result? {
        let width = image.width
        let height = image.height
        guard
            width > 2,
            height > 2,
            width <= 1024,
            height <= 256,
            let colorSpace = CGColorSpace(name: CGColorSpace.sRGB)
        else {
            return nil
        }
        var pixels = [UInt8](repeating: 0, count: width * height * 4)
        let decoded = pixels.withUnsafeMutableBytes { bytes -> Bool in
            guard let context = CGContext(
                data: bytes.baseAddress,
                width: width,
                height: height,
                bitsPerComponent: 8,
                bytesPerRow: width * 4,
                space: colorSpace,
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue | CGBitmapInfo.byteOrder32Big.rawValue
            ) else { return false }
            context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
            return true
        }
        guard decoded else { return nil }

        let offsets = stride(from: 0, to: pixels.count, by: 4)
        // A genuinely transparent source needs no background estimation.
        if offsets.filter({ pixels[$0 + 3] < 16 }).count > width * height / 5 {
            return Result(image: image, isTemplate: false)
        }

        // The menu bar is translucent, so a crop's background is a piece of
        // wallpaper: it can change across the crop and from top to bottom, and
        // a wallpaper edge can cut through it diagonally. A single color, or
        // even one color per column, leaves that gradient behind as a visible
        // patch. Estimate the background at the top and the bottom of every
        // column, then read it at each pixel by blending between the two.
        func edgeBackground(rows: [Int]) -> [[Double]] {
            (0..<width).map { x -> [Double] in
                let window = max(0, x - 2)...min(width - 1, x + 2)
                return (0..<3).map { channel -> Double in
                    var values = [Double]()
                    for column in window {
                        for y in rows {
                            values.append(Double(pixels[(y * width + column) * 4 + channel]) / 255)
                        }
                    }
                    values.sort()
                    return values.isEmpty ? 0 : values[values.count / 2]
                }
            }
        }
        let topBackgrounds = edgeBackground(rows: Array(0..<min(2, height)))
        let bottomBackgrounds = edgeBackground(rows: Array((height - min(2, height))..<height))

        func background(of offset: Int) -> [Double] {
            let pixel = offset / 4
            let x = pixel % width
            let y = pixel / width
            let fraction = height > 1 ? Double(y) / Double(height - 1) : 0
            let top = topBackgrounds[x]
            let bottom = bottomBackgrounds[x]
            return (0..<3).map { top[$0] + ($0 < bottom.count ? (bottom[$0] - top[$0]) * fraction : 0) }
        }

        let luminance: ([Double]) -> Double = { $0[0] * 0.2126 + $0[1] * 0.7152 + $0[2] * 0.0722 }
        let differences = offsets.map { offset -> Double in
            luminance((0..<3).map { Double(pixels[offset + $0]) / 255 }) - luminance(background(of: offset))
        }.sorted()
        let edgeCount = max(1, differences.count / 50)
        let bright = differences.suffix(edgeCount).reduce(0, +) / Double(edgeCount)
        let dark = -differences.prefix(edgeCount).reduce(0, +) / Double(edgeCount)
        let colorContrasts = offsets.map { offset -> Double in
            let pixelBackground = background(of: offset)
            return (0..<3).map { abs(Double(pixels[offset + $0]) / 255 - pixelBackground[$0]) }.max() ?? 0
        }
        // Saturated colors may have exactly the background's luminance.
        // Detect foreground in RGB, not brightness alone.
        guard colorContrasts.max() ?? 0 > 0.08 else { return nil }
        let foreground: Double = bright >= dark ? 1 : 0

        var alphas = [Double]()
        var foregroundCount = 0
        var coloredCount = 0
        for offset in offsets {
            let pixelBackground = background(of: offset)
            let direction = pixelBackground.map { foreground - $0 }
            let denominator = direction.reduce(0) { $0 + $1 * $1 }
            let color = (0..<3).map { Double(pixels[offset + $0]) / 255 }
            guard denominator > 0.01 else {
                alphas.append(0)
                continue
            }
            let projection = (0..<3).reduce(0.0) { $0 + (color[$1] - pixelBackground[$1]) * direction[$1] }
            let alpha = max(0, min(1, projection / denominator))
            alphas.append(alpha)
            if (0..<3).contains(where: { abs(color[$0] - pixelBackground[$0]) > 0.12 }) {
                foregroundCount += 1
                let residual = (0..<3).map { abs(color[$0] - pixelBackground[$0] - alpha * direction[$0]) }.max() ?? 0
                if residual > 0.07 { coloredCount += 1 }
            }
        }
        guard foregroundCount >= 3 else { return nil }

        // A wallpaper edge inside the crop leaves a residual, which on its own
        // would call a white or black glyph colored and keep that wallpaper in
        // the result. Decide from the glyph's own color instead. A gray glyph
        // moves every channel toward the foreground by the same fraction; a
        // colored one, like Stats' red and blue text, does not.
        var solidCount = 0
        var chromaticCount = 0
        for offset in offsets {
            let pixelBackground = background(of: offset)
            let fractions = (0..<3).map { channel -> Double in
                let color = Double(pixels[offset + channel]) / 255
                return foreground > 0.5
                    ? (color - pixelBackground[channel]) / max(0.05, 1 - pixelBackground[channel])
                    : (pixelBackground[channel] - color) / max(0.05, pixelBackground[channel])
            }
            guard let strongest = fractions.max(), strongest > 0.35 else {
                continue
            }
            solidCount += 1
            if strongest - (fractions.min() ?? 0) > 0.2 {
                chromaticCount += 1
            }
        }
        let isTemplate = solidCount < 8
            ? coloredCount <= max(3, foregroundCount / 20)
            : chromaticCount * 12 < solidCount
        let peakAlpha = alphas.max() ?? 1
        // Anything fainter than this is wallpaper left over from an edge that
        // crosses the crop, not glyph. The remainder is curved so that what
        // stays keeps soft edges.
        let noiseFloor = 0.26
        func cleaned(_ alpha: Double, peak: Double) -> Double {
            let scaled = max(0, alpha - noiseFloor) / max(0.1, peak - noiseFloor)
            return min(1, pow(min(1, scaled), 1.3))
        }
        // Compute the glyph's alpha first, then drop faint regions that never
        // reach full strength. A wallpaper edge crossing the crop survives the
        // noise floor as a thin, weak streak; the glyph itself always has
        // solid pixels, so only keep what is connected to one.
        var alphaMap = [Double](repeating: 0, count: width * height)
        for (index, offset) in offsets.enumerated() {
            if isTemplate {
                alphaMap[index] = cleaned(alphas[index], peak: peakAlpha)
            } else {
                let pixelBackground = background(of: offset)
                let color = (0..<3).map { Double(pixels[offset + $0]) / 255 }
                let unmixed = (0..<3).map { channel -> Double in
                    let delta = color[channel] - pixelBackground[channel]
                    return delta >= 0 ? delta / max(0.01, 1 - pixelBackground[channel]) : -delta / max(0.01, pixelBackground[channel])
                }.max() ?? 0
                alphaMap[index] = cleaned(unmixed, peak: 1)
            }
        }

        let strongAlpha = 0.6
        var keep = [Bool](repeating: false, count: alphaMap.count)
        var stack = (0..<alphaMap.count).filter { alphaMap[$0] >= strongAlpha }
        for index in stack {
            keep[index] = true
        }
        while let index = stack.popLast() {
            let x = index % width
            let y = index / width
            for dy in -1...1 {
                for dx in -1...1 {
                    let nx = x + dx
                    let ny = y + dy
                    guard nx >= 0, nx < width, ny >= 0, ny < height else { continue }
                    let neighbor = ny * width + nx
                    guard !keep[neighbor], alphaMap[neighbor] > 0 else { continue }
                    keep[neighbor] = true
                    stack.append(neighbor)
                }
            }
        }

        var output = [UInt8](repeating: 0, count: pixels.count)
        for (index, offset) in offsets.enumerated() {
            let alpha = keep[index] ? alphaMap[index] : 0
            guard alpha > 0 else { continue }
            if isTemplate {
                // Store black + alpha; AppKit applies the current appearance's
                // label color. Keep soft edges and relative glyph opacity.
                output[offset + 3] = UInt8((alpha * 255).rounded())
            } else {
                // Color-to-alpha unmixing preserves multicolor status glyphs.
                let pixelBackground = background(of: offset)
                for channel in 0..<3 {
                    let color = Double(pixels[offset + channel]) / 255
                    let component = color - pixelBackground[channel] * (1 - alpha)
                    output[offset + channel] = UInt8((max(0, min(alpha, component)) * 255).rounded())
                }
                output[offset + 3] = UInt8((alpha * 255).rounded())
            }
        }

        guard
            let provider = CGDataProvider(data: Data(output) as CFData),
            let result = CGImage(
                width: width,
                height: height,
                bitsPerComponent: 8,
                bitsPerPixel: 32,
                bytesPerRow: width * 4,
                space: colorSpace,
                bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue | CGBitmapInfo.byteOrder32Big.rawValue),
                provider: provider,
                decode: nil,
                shouldInterpolate: true,
                intent: .defaultIntent
            )
        else {
            return nil
        }
        return Result(image: result, isTemplate: isTemplate)
    }
}
