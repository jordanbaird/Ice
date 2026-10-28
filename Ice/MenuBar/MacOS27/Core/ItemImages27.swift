//
//  ItemImages27.swift
//  Ice
//

import CoreGraphics
import Foundation

/// Pure rules for menu bar item images on macOS 27.
enum ItemImages27 {
    /// The pixel rectangle of an item inside a capture of its display's menu bar strip,
    /// or `nil` if the item is not on that strip. Frames are in global points with the
    /// origin at the top left, like the capture.
    static func cropRect(itemFrame: CGRect, stripFrame: CGRect, scale: CGFloat) -> CGRect? {
        let clipped = itemFrame.intersection(stripFrame)
        guard !clipped.isNull, clipped.width >= itemFrame.width * 0.9 else {
            return nil
        }
        return CGRect(
            x: ((clipped.minX - stripFrame.minX) * scale).rounded(.down),
            y: ((clipped.minY - stripFrame.minY) * scale).rounded(.down),
            width: (clipped.width * scale).rounded(.up),
            height: (clipped.height * scale).rounded(.up)
        )
    }

    /// Below this share of the glyph's own contrast, a pixel is taken for bar, not glyph.
    private static let noiseFloor = 0.06
    /// A tile whose pixels all sit this close to the background holds no glyph.
    private static let emptyTileDistance = 8.0
    /// Further than this from the tile's own colour, a column's edge is glyph, not bar.
    private static let maximumColumnDrift = 40.0

    /// The background colour of a captured item, taken from the pixels along its edges.
    ///
    /// A capture of the menu bar carries the bar behind the glyph. The edges of an item's
    /// rectangle are background almost everywhere, so the most common colour among them is
    /// the background. Pixels are `RGBA`, eight bits each, row by row.
    static func backgroundColor(pixels: [UInt8], width: Int, height: Int) -> (r: UInt8, g: UInt8, b: UInt8) {
        var counts = [UInt32: Int]()
        func count(x: Int, y: Int) {
            let offset = (y * width + x) * 4
            guard offset + 2 < pixels.count else {
                return
            }
            let key = UInt32(pixels[offset]) << 16 | UInt32(pixels[offset + 1]) << 8 | UInt32(pixels[offset + 2])
            counts[key, default: 0] += 1
        }
        for x in 0..<width {
            count(x: x, y: 0)
            count(x: x, y: height - 1)
        }
        for y in 0..<height {
            count(x: 0, y: y)
            count(x: width - 1, y: y)
        }
        guard let common = counts.max(by: { $0.value < $1.value })?.key else {
            return (0, 0, 0)
        }
        return (UInt8((common >> 16) & 0xff), UInt8((common >> 8) & 0xff), UInt8(common & 0xff))
    }

    /// The same pixels with the background made transparent, so the glyph can be drawn on
    /// any colour.
    ///
    /// The capture holds the glyph already blended into the bar, so a pixel's opacity is
    /// how far it moved from the bar towards the glyph's own colour, not how far it lies
    /// from the bar in absolute terms. Measuring absolutely washes out a glyph that is
    /// close in colour to the bar; measuring as a share keeps it whole and still softens
    /// the glyph's edges. The glyph's colour is taken to be that of the pixel furthest
    /// from the background, and each pixel's colour is unblended from the background.
    static func removingBackground(
        pixels: [UInt8],
        width: Int,
        height: Int,
        background: (r: UInt8, g: UInt8, b: UInt8),
        tone: GlyphTone? = nil
    ) -> [UInt8] {
        let count = min(pixels.count, width * height * 4)
        let backgroundChannels = [Double(background.r), Double(background.g), Double(background.b)]

        // The bar is translucent, so the wallpaper behind it shows through, and it shows
        // through with all of its structure. Measured on macOS 27.0, down one 29-row column
        // the red channel ran 109 to 130 while the blue fell 202 to 166, with the turn in
        // the middle rows; another column stayed flat for two thirds and then turned. Across
        // the width of a single item, in one row, the same colour barely moves. A background
        // guessed by interpolating down the rows is therefore out by up to 20 of 255 in the
        // middle rows, and that residue is the pale box that showed behind every glyph and
        // made the tiles too wide. So each row takes its own colour, one from the left edge
        // and one from the right, and every pixel is measured against the blend of the two at
        // its own column. A row the glyph covers edge to edge keeps the tile's commonest
        // colour instead of erasing itself.
        func edgeBackground(row: Int, columns: [Int]) -> (colour: [Double], column: Int) {
            var closest = backgroundChannels
            var closestColumn = columns.first ?? 0
            var closestDrift = Double.infinity
            for x in columns {
                let index = (row * width + x) * 4
                guard index + 2 < count else {
                    continue
                }
                let candidate = (0..<3).map { Double(pixels[index + $0]) }
                let drift = (0..<3).reduce(0.0) { max($0, abs(candidate[$1] - backgroundChannels[$1])) }
                if drift < closestDrift {
                    closestDrift = drift
                    closest = candidate
                    closestColumn = x
                }
            }
            return closestDrift <= maximumColumnDrift ? (closest, closestColumn) : (backgroundChannels, closestColumn)
        }

        let leftColumns = [0, 1].filter { $0 < width }
        let rightColumns = [width - 2, width - 1].filter { $0 >= 0 }
        var leftBackgrounds = [(colour: [Double], column: Int)]()
        var rightBackgrounds = [(colour: [Double], column: Int)]()
        for y in 0..<height {
            leftBackgrounds.append(edgeBackground(row: y, columns: leftColumns))
            rightBackgrounds.append(edgeBackground(row: y, columns: rightColumns))
        }

        func blendedBackground(at index: Int) -> [Double] {
            let pixel = index / 4
            let row = pixel / width
            guard row < leftBackgrounds.count else {
                return backgroundChannels
            }
            let left = leftBackgrounds[row]
            let right = rightBackgrounds[row]
            let span = Double(right.column - left.column)
            let share = span > 0 ? min(1, max(0, Double(pixel % width - left.column) / span)) : 0
            return (0..<3).map { left.colour[$0] + (right.colour[$0] - left.colour[$0]) * share }
        }

        func distance(at index: Int) -> Double {
            let local = blendedBackground(at: index)
            return (0..<3).reduce(0) { furthest, channel in
                max(furthest, abs(Double(pixels[index + channel]) - local[channel]))
            }
        }

        var glyphDistance = 0.0
        for index in stride(from: 0, to: count, by: 4) {
            glyphDistance = max(glyphDistance, distance(at: index))
        }

        var result = pixels
        guard glyphDistance > emptyTileDistance else {
            for index in stride(from: 0, to: count, by: 4) {
                result[index + 3] = 0
            }
            return result
        }

        // A textured wallpaper defeats any guess at the background. Over an aerial photograph
        // the bar showed road markings, cars and asphalt within a single item's width, and
        // every one of them sat far from the estimate and came through as glyph (measured on
        // macOS 27.0). The glyph itself is drawn in one colour, though, while a photograph
        // scatters: among the pixels clearly off the background, the commonest colour is the
        // glyph's. So a pixel counts as glyph only as far as it also comes close to that colour.
        // A tile with no dominant colour — an icon drawn in several — keeps the background
        // measure alone, so colour icons are not eaten away.
        let glyphColour = dominantColour(
            among: stride(from: 0, to: count, by: 4).filter { distance(at: $0) >= glyphDistance * farShare },
            pixels: pixels,
            tone: tone
        )
        let backgroundToGlyph = glyphColour.map { colour in
            (0..<3).reduce(0.0) { max($0, abs(backgroundChannels[$1] - colour[$1])) }
        } ?? 0

        for index in stride(from: 0, to: count, by: 4) {
            var opacity = min(1, distance(at: index) / glyphDistance)
            if let glyphColour, backgroundToGlyph > emptyTileDistance {
                // Closeness to the glyph alone decides once the glyph's colour is known: over a
                // photograph the distance from the background estimate is unreliable for the
                // glyph as much as for the wallpaper, and taking the lower of the two left the
                // glyph itself part-transparent. A background that merely drifts towards the
                // glyph's colour stays under the floor.
                let fromGlyph = (0..<3).reduce(0.0) { max($0, abs(Double(pixels[index + $1]) - glyphColour[$1])) }
                let closeness = 1 - fromGlyph / backgroundToGlyph
                opacity = min(1, max(0, (closeness - glyphPriorFloor) / (1 - glyphPriorFloor)))
            }
            guard opacity > noiseFloor else {
                result[index + 3] = 0
                continue
            }
            result[index + 3] = UInt8((opacity * 255).rounded())
            let local = blendedBackground(at: index)
            for channel in 0..<3 {
                let unblended = (Double(pixels[index + channel]) - local[channel] * (1 - opacity)) / opacity
                result[index + channel] = UInt8(min(255, max(0, unblended.rounded())))
            }
        }
        return result
    }

    /// The same pixels with every separate mark that holds no solid pixel made transparent.
    ///
    /// Wallpaper detail in the glyph's own colour survives any colour test: over an aerial
    /// photograph, a white road marking under the spot where hidden items are photographed
    /// came through as a faint streak beside every one of them, at the very same pixels
    /// (measured on macOS 27.0). A glyph's own soft rim touches its solid core, while such a
    /// mark stands apart and never reaches solid, so marks are kept or dropped whole.
    static func droppingFaintMarks(pixels: [UInt8], width: Int, height: Int) -> [UInt8] {
        let count = width * height
        guard count > 0, pixels.count >= count * 4 else {
            return pixels
        }
        var result = pixels
        var visited = [Bool](repeating: false, count: count)
        for start in 0..<count where !visited[start] && pixels[start * 4 + 3] > visibleAlpha {
            // Gather the mark this pixel belongs to, neighbours in all eight directions.
            var mark = [start]
            var strongest = pixels[start * 4 + 3]
            visited[start] = true
            var cursor = 0
            while cursor < mark.count {
                let pixel = mark[cursor]
                cursor += 1
                let x = pixel % width
                let y = pixel / width
                for dy in -1...1 {
                    for dx in -1...1 where dx != 0 || dy != 0 {
                        let nx = x + dx
                        let ny = y + dy
                        guard nx >= 0, nx < width, ny >= 0, ny < height else {
                            continue
                        }
                        let neighbour = ny * width + nx
                        guard !visited[neighbour], pixels[neighbour * 4 + 3] > visibleAlpha else {
                            continue
                        }
                        visited[neighbour] = true
                        strongest = max(strongest, pixels[neighbour * 4 + 3])
                        mark.append(neighbour)
                    }
                }
            }
            guard strongest < solidMark else {
                continue
            }
            for pixel in mark {
                result[pixel * 4 + 3] = 0
            }
        }
        return result
    }

    /// The opacity a mark must reach somewhere to be part of the glyph.
    private static let solidMark: UInt8 = 160

    /// Pixels at least this share of the glyph's distance from the background are clearly
    /// off it, and so tell the glyph's colour.
    private static let farShare = 0.5

    /// The share of those pixels the near-white or the near-black ones must hold to count as
    /// the glyph. Below it the icon is taken to be drawn in colour.
    private static let extremeShare = 0.2

    /// How near to white or black a channel must be for the pixel to be of a template glyph.
    private static let extremeMargin = 55

    /// How close to the glyph's colour a pixel must come before it counts as glyph at all. The
    /// background's own drift towards that colour — a gradient, a lighter patch of wallpaper —
    /// stays below it, and so do mid-tones of a photograph.
    private static let glyphPriorFloor = 0.25

    /// The glyph's colour among the given pixels: near white or near black, whichever of the
    /// two they hold more of, as long as that is a real share of them.
    ///
    /// MenuBarAgent draws the active bar's template glyphs in white or in black. Looking only
    /// at those two keeps a photograph's own dark patches from passing for the glyph: behind
    /// the clock, asphalt outnumbered the thin strokes of its text, so the commonest colour
    /// among clearly off-background pixels was the road, not the glyph (measured on macOS 27.0).
    private static func dominantColour(among indices: [Int], pixels: [UInt8], tone: GlyphTone?) -> [Double]? {
        guard indices.count >= 4 else {
            return nil
        }
        var white = (count: 0, sum: [0.0, 0.0, 0.0])
        var black = (count: 0, sum: [0.0, 0.0, 0.0])
        for index in indices where index + 2 < pixels.count {
            let channels = (0..<3).map { Int(pixels[index + $0]) }
            if channels.allSatisfy({ $0 >= 255 - extremeMargin }) {
                white.count += 1
                for channel in 0..<3 {
                    white.sum[channel] += Double(channels[channel])
                }
            } else if channels.allSatisfy({ $0 <= extremeMargin }) {
                black.count += 1
                for channel in 0..<3 {
                    black.sum[channel] += Double(channels[channel])
                }
            }
        }
        // A tone decided for the whole bar is trusted over the tile's own count, which a dark
        // patch of wallpaper can tip the wrong way.
        let top: (count: Int, sum: [Double])
        switch tone {
        case .light?: top = white
        case .dark?: top = black
        case nil: top = white.count >= black.count ? white : black
        }
        guard top.count >= 4, tone != nil || Double(top.count) >= Double(indices.count) * extremeShare else {
            return nil
        }
        return top.sum.map { $0 / Double(top.count) }
    }

    /// Which colour MenuBarAgent drew a bar's glyphs in.
    enum GlyphTone: Sendable {
        case light
        case dark
    }

    /// How a tile leans: how many of its pixels, clearly apart from the tile's commonest colour,
    /// are near white and how many near black.
    ///
    /// MenuBarAgent draws every glyph on a bar in the same colour, so summed over the bar the
    /// glyphs outvote whatever wallpaper sits behind a few of them. Decided tile by tile, the
    /// battery over a patch of dark asphalt judged its glyph black and came out as a black box
    /// with the battery cut out of it (measured on macOS 27.0, over an aerial photograph). The
    /// tile's own background is not counted, being close to the tile's commonest colour.
    static func toneVotes(pixels: [UInt8], width: Int, height: Int) -> (light: Int, dark: Int) {
        let count = min(pixels.count, width * height * 4)
        guard count >= 4 else {
            return (0, 0)
        }
        let common = backgroundColor(pixels: pixels, width: width, height: height)
        let base = [Int(common.r), Int(common.g), Int(common.b)]
        var light = 0
        var dark = 0
        for index in stride(from: 0, to: count, by: 4) {
            let channels = (0..<3).map { Int(pixels[index + $0]) }
            let apart = (0..<3).reduce(0) { max($0, abs(channels[$1] - base[$1])) }
            guard apart >= toneVoteDistance else {
                continue
            }
            if channels.allSatisfy({ $0 >= 255 - extremeMargin }) {
                light += 1
            } else if channels.allSatisfy({ $0 <= extremeMargin }) {
                dark += 1
            }
        }
        return (light, dark)
    }

    /// How far from the tile's commonest colour a pixel must be to cast a vote.
    private static let toneVoteDistance = 60

    /// The tags whose frames are the same in both reads, give or take a point.
    ///
    /// The bar re-lays out whenever an item is shown or hidden, or when Ice's own item
    /// leaves it, and a capture taken across that re-layout cuts between icons: the stored
    /// images then hold slivers of two neighbours or plain bar (measured on macOS 27.0,
    /// after the Ice icon was switched off while items were being photographed). Reading
    /// the frames again after the capture and keeping only what stayed put throws those
    /// away, so the next capture can store them properly.
    static func settledTags(before: [String: CGRect], after: [String: CGRect], tolerance: CGFloat = 1) -> Set<String> {
        var settled = Set<String>()
        for (tag, frame) in before {
            guard let later = after[tag] else {
                continue
            }
            let moved = max(
                abs(later.minX - frame.minX),
                abs(later.minY - frame.minY),
                abs(later.width - frame.width),
                abs(later.height - frame.height)
            )
            if moved <= tolerance {
                settled.insert(tag)
            }
        }
        return settled
    }

    /// Anything fainter than this is a trace of a neighbouring item, not the glyph.
    private static let visibleAlpha: UInt8 = 16

    /// The columns the glyph itself covers, or `nil` when the tile holds nothing.
    ///
    /// MenuBarAgent pads items unevenly, so a captured tile has anywhere from no margin to
    /// a dozen points of it (measured on macOS 27.0). Drawing the tiles side by side then
    /// spaces the glyphs unevenly, which is why the Ice Bar and the layout window trim each
    /// tile to its glyph and add a margin of their own.
    static func glyphColumns(pixels: [UInt8], width: Int, height: Int) -> ClosedRange<Int>? {
        var first: Int?
        var last: Int?
        for x in 0..<width {
            let covered = (0..<height).contains { y in
                let index = (y * width + x) * 4 + 3
                return index < pixels.count && pixels[index] > visibleAlpha
            }
            guard covered else {
                continue
            }
            if first == nil {
                first = x
            }
            last = x
        }
        guard let first, let last else {
            return nil
        }
        return first...last
    }

    /// The same pixels in one colour, keeping every pixel's opacity.
    ///
    /// MenuBarAgent draws a glyph light or dark to suit whatever sits behind the menu bar,
    /// so a captured glyph can be the wrong colour for the Ice Bar's own flat background.
    /// Recolouring gives the panel one readable look, the way a template image behaves.
    static func tinted(pixels: [UInt8], colour: (r: UInt8, g: UInt8, b: UInt8)) -> [UInt8] {
        var result = pixels
        for index in stride(from: 0, to: pixels.count, by: 4) {
            result[index] = colour.r
            result[index + 1] = colour.g
            result[index + 2] = colour.b
        }
        return result
    }

    /// Whether a tile photographs an item caught mid-fade rather than the item itself.
    ///
    /// An item fading in or out is drawn part-transparent, so its capture holds a faint glyph
    /// inside a wide haze of menu bar that no background estimate can account for — the pale,
    /// too-wide tiles that showed in the Ice Bar. Frames cannot catch this: a fading item
    /// keeps its frame, it only loses opacity. The proportions can: measured on macOS 27.0,
    /// such tiles carry 1.6–2.3 % opaque pixels against 21–26 % faint ones, while items
    /// photographed standing still carry 5–20 % against 3–9 %. Far more haze than ink is the
    /// signature, and three times as much separates the two with a wide margin either side.
    static func isFaded(pixels: [UInt8], width: Int, height: Int) -> Bool {
        var ink = 0
        var haze = 0
        for index in stride(from: 3, to: min(pixels.count, width * height * 4), by: 4) {
            let alpha = pixels[index]
            if alpha > solidAlpha {
                ink += 1
            } else if alpha > visibleAlpha {
                haze += 1
            }
        }
        guard ink > 0 else {
            return haze > 0
        }
        return haze > ink * hazeToInkLimit
    }

    /// Whether a finished tile still carries the bar behind its glyph.
    ///
    /// A tile that keeps the bar fails in one of two ways, and neither looks like a fade.
    /// Nothing was cut at all, and the tile is nearly solid: a glyph covers 5–20 % of its tile
    /// (measured here), while a tile with the bar left in came to 58 %. Or the colour test let
    /// the wallpaper's own texture through, and the tile is mostly haze: good tiles hold 3–9 %,
    /// against 22 % and 39 % in the two that were kept.
    ///
    /// The numbers are @jasonsmithio's, measured on three tiles stored on a notched MacBook that
    /// stayed wrong for a week (jordanbaird/Ice#995). Refusing a good tile by mistake costs a
    /// photograph; keeping a bad one used to cost the user that icon for good.
    static func keepsTheBar(pixels: [UInt8], width: Int, height: Int) -> Bool {
        let count = min(pixels.count / 4, width * height)
        guard count > 0 else {
            return false
        }
        var ink = 0
        var haze = 0
        for index in stride(from: 3, to: count * 4, by: 4) {
            let alpha = pixels[index]
            if alpha > solidAlpha {
                ink += 1
            } else if alpha > visibleAlpha {
                haze += 1
            }
        }
        let total = Double(count)
        return Double(ink) / total > inkShareLimit || Double(haze) / total > hazeShareLimit
    }

    /// How much of a tile a glyph may cover before the tile is the bar itself.
    private static let inkShareLimit = 0.45

    /// How much of a tile may be left half-transparent before it is wallpaper, not a glyph.
    private static let hazeShareLimit = 0.15

    /// Opaque enough to be the glyph itself rather than a trace of the bar.
    private static let solidAlpha: UInt8 = 200

    /// How much more haze than ink a tile may hold before it counts as a fade.
    private static let hazeToInkLimit = 3

    /// A stable file name for an item's image, safe to use on disk.
    static func fileName(forTag tag: String) -> String {
        var hash: UInt64 = 0xcbf2_9ce4_8422_2325
        for byte in tag.utf8 {
            hash ^= UInt64(byte)
            hash &*= 0x0000_0100_0000_01b3
        }
        return String(format: "%016llx.png", hash)
    }
}

/// Decides when an application may be shown for a moment to photograph its item.
struct PhotoSchedule27 {
    static let minimumInterval: TimeInterval = 600

    /// A capture can come back with nothing usable: the item was folded into macOS's own
    /// overflow, or its tile was refused as a fade. The item then has no glyph at all, which
    /// is worth another try long before the usual ten minutes.
    static let retryInterval: TimeInterval = 45

    private var nextAttempts = [String: TimeInterval]()

    func mayPhotograph(bundleID: String, now: TimeInterval) -> Bool {
        guard let next = nextAttempts[bundleID] else {
            return true
        }
        return now >= next
    }

    mutating func recordAttempt(bundleID: String, now: TimeInterval, stored: Bool = true) {
        nextAttempts[bundleID] = now + (stored ? Self.minimumInterval : Self.retryInterval)
    }
}
