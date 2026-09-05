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
        guard width > 2, height > 2, width <= 1024, height <= 256,
              let colorSpace = CGColorSpace(name: CGColorSpace.sRGB) else { return nil }
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

        let border = (0..<height).flatMap { y in
            (0..<width).compactMap { x -> Int? in
                x < 2 || y < 2 || x >= width - 2 || y >= height - 2 ? (y * width + x) * 4 : nil
            }
        }
        // A median rejects glyph strokes touching an AX frame's edges. A
        // corner color alone can mistake such a stroke for the background.
        let background = (0..<3).map { channel -> Double in
            let values = border.map { Double(pixels[$0 + channel]) / 255 }.sorted()
            return values[values.count / 2]
        }
        let luminance: ([Double]) -> Double = { $0[0] * 0.2126 + $0[1] * 0.7152 + $0[2] * 0.0722 }
        let backgroundLuminance = luminance(background)
        let differences = offsets.map { offset in
            luminance((0..<3).map { Double(pixels[offset + $0]) / 255 }) - backgroundLuminance
        }.sorted()
        let edgeCount = max(1, differences.count / 50)
        let bright = differences.suffix(edgeCount).reduce(0, +) / Double(edgeCount)
        let dark = -differences.prefix(edgeCount).reduce(0, +) / Double(edgeCount)
        let colorContrasts = offsets.map { offset in
            (0..<3).map { abs(Double(pixels[offset + $0]) / 255 - background[$0]) }.max() ?? 0
        }
        // Saturated colors may have exactly the background's luminance.
        // Detect foreground in RGB, not brightness alone.
        guard colorContrasts.max() ?? 0 > 0.08 else { return nil }
        let foreground: Double = bright >= dark ? 1 : 0
        let direction = background.map { foreground - $0 }
        let denominator = direction.reduce(0) { $0 + $1 * $1 }
        guard denominator > 0.01 else { return nil }

        var alphas = [Double]()
        var foregroundCount = 0
        var coloredCount = 0
        for offset in offsets {
            let color = (0..<3).map { Double(pixels[offset + $0]) / 255 }
            let projection = (0..<3).reduce(0.0) { $0 + (color[$1] - background[$1]) * direction[$1] }
            let alpha = max(0, min(1, projection / denominator))
            alphas.append(alpha)
            if (0..<3).contains(where: { abs(color[$0] - background[$0]) > 0.12 }) {
                foregroundCount += 1
                let residual = (0..<3).map { abs(color[$0] - background[$0] - alpha * direction[$0]) }.max() ?? 0
                if residual > 0.07 { coloredCount += 1 }
            }
        }
        guard foregroundCount >= 3 else { return nil }
        let isTemplate = coloredCount <= max(3, foregroundCount / 20)
        let peakAlpha = alphas.max() ?? 1
        var output = [UInt8](repeating: 0, count: pixels.count)
        for (index, offset) in offsets.enumerated() {
            if isTemplate {
                // Store black + alpha; AppKit applies the current appearance's
                // label color. Keep soft edges and relative glyph opacity.
                let alpha = max(0, alphas[index] - 0.025) / max(0.1, peakAlpha - 0.025)
                output[offset + 3] = UInt8((min(1, alpha) * 255).rounded())
            } else {
                // Color-to-alpha unmixing preserves multicolor status glyphs.
                let color = (0..<3).map { Double(pixels[offset + $0]) / 255 }
                let alpha = (0..<3).map { channel -> Double in
                    let delta = color[channel] - background[channel]
                    return delta >= 0 ? delta / max(0.01, 1 - background[channel]) : -delta / max(0.01, background[channel])
                }.max() ?? 0
                guard alpha > 0.04 else { continue }
                let boundedAlpha = min(1, alpha)
                for channel in 0..<3 {
                    let component = color[channel] - background[channel] * (1 - boundedAlpha)
                    output[offset + channel] = UInt8((max(0, min(boundedAlpha, component)) * 255).rounded())
                }
                output[offset + 3] = UInt8((boundedAlpha * 255).rounded())
            }
        }

        guard let provider = CGDataProvider(data: Data(output) as CFData),
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
              ) else { return nil }
        return Result(image: result, isTemplate: isTemplate)
    }
}
