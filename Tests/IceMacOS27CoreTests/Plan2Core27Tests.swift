import CoreGraphics
import Foundation
import Testing
@testable import IceMacOS27Core

@Suite("Temporary allowances")
struct TemporaryAllowance27Tests {
    let layout: [String: MacOS27Section] = [
        "ru.keepcoder.Telegram": .hidden,
        "com.caldis.Mos": .alwaysHidden,
    ]

    @Test("A temporarily shown application leaves the concealed set")
    func removed() {
        let sets = ConcealmentPlanner27.concealedSets(layout: layout, state: .allHidden, temporarilyShown: ["ru.keepcoder.Telegram"])
        #expect(sets == [["com.caldis.Mos"]])
    }

    @Test("Showing the only concealed application needs no assertion")
    func nothingLeft() {
        let sets = ConcealmentPlanner27.concealedSets(layout: layout, state: .hiddenRevealed, temporarilyShown: ["com.caldis.Mos"])
        #expect(sets.isEmpty)
    }

    @Test("Without temporary allowances the sets are unchanged")
    func unchanged() {
        let plain = ConcealmentPlanner27.concealedSets(layout: layout, state: .allHidden)
        #expect(ConcealmentPlanner27.concealedSets(layout: layout, state: .allHidden, temporarilyShown: []) == plain)
    }
}

@Suite("ItemImages27")
struct ItemImages27Tests {
    @Test("An item on a 1x display crops to its own frame")
    func externalCrop() {
        let rect = ItemImages27.cropRect(
            itemFrame: CGRect(x: 1478, y: 2, width: 33, height: 24),
            stripFrame: CGRect(x: 0, y: 0, width: 1920, height: 30),
            scale: 1
        )
        #expect(rect == CGRect(x: 1478, y: 2, width: 33, height: 24))
    }

    @Test("An item on a 2x display left of the primary one crops in pixels")
    func builtInCrop() {
        let rect = ItemImages27.cropRect(
            itemFrame: CGRect(x: -442, y: 102.5, width: 33, height: 24),
            stripFrame: CGRect(x: -1512, y: 98, width: 1512, height: 33),
            scale: 2
        )
        #expect(rect == CGRect(x: 2140, y: 9, width: 66, height: 48))
    }

    @Test("An item on another display has no crop")
    func otherDisplay() {
        let rect = ItemImages27.cropRect(
            itemFrame: CGRect(x: 1478, y: 2, width: 33, height: 24),
            stripFrame: CGRect(x: -1512, y: 98, width: 1512, height: 33),
            scale: 2
        )
        #expect(rect == nil)
    }

    @Test("File names are stable, distinct and safe")
    func fileNames() {
        let name = ItemImages27.fileName(forTag: "eu.exelban.Stats:Item-0")
        #expect(name == ItemImages27.fileName(forTag: "eu.exelban.Stats:Item-0"))
        #expect(name != ItemImages27.fileName(forTag: "eu.exelban.Stats:Item-1"))
        #expect(name.hasSuffix(".png"))
        #expect(!name.contains("/") && !name.contains(":"))
    }

    @Test("Premultiplying matches rounding each channel times its opacity")
    func premultiplied() {
        var pixels = [UInt8]()
        for colour in stride(from: 0, through: 255, by: 17) {
            for alpha in stride(from: 0, through: 255, by: 15) {
                pixels += [UInt8(colour), UInt8(255 - colour), 128, UInt8(alpha)]
            }
        }
        let result = ItemImages27.premultiplied(pixels: pixels)
        for index in stride(from: 0, to: pixels.count, by: 4) {
            let opacity = Double(pixels[index + 3]) / 255
            for channel in 0..<3 {
                #expect(result[index + channel] == UInt8((Double(pixels[index + channel]) * opacity).rounded()))
            }
            #expect(result[index + 3] == pixels[index + 3])
        }
    }
}

@Suite("ItemImageRetention27")
struct ItemImageRetention27Tests {
    private let day: TimeInterval = 24 * 60 * 60
    private let seen = Date(timeIntervalSinceReferenceDate: 0)

    @Test("An image is kept for thirty days after its item was last seen")
    func lifetime() {
        #expect(!ItemImageRetention27.isExpired(lastSeen: seen, now: seen.addingTimeInterval(29 * day)))
        #expect(ItemImageRetention27.isExpired(lastSeen: seen, now: seen.addingTimeInterval(30 * day)))
    }

    @Test("A sighting is noted again at most once a day")
    func refresh() {
        #expect(!ItemImageRetention27.needsRefresh(lastSeen: seen, now: seen.addingTimeInterval(day - 1)))
        #expect(ItemImageRetention27.needsRefresh(lastSeen: seen, now: seen.addingTimeInterval(day)))
    }
}

@Suite("PhotoSchedule27")
struct PhotoSchedule27Tests {
    @Test("An application is photographed at most once every ten minutes")
    func interval() {
        var schedule = PhotoSchedule27()
        #expect(schedule.mayPhotograph(bundleID: "ru.keepcoder.Telegram", now: 0))
        schedule.recordAttempt(bundleID: "ru.keepcoder.Telegram", now: 0)
        #expect(!schedule.mayPhotograph(bundleID: "ru.keepcoder.Telegram", now: 599))
        #expect(schedule.mayPhotograph(bundleID: "ru.keepcoder.Telegram", now: 600))
    }

    @Test("Applications are scheduled independently")
    func independent() {
        var schedule = PhotoSchedule27()
        schedule.recordAttempt(bundleID: "ru.keepcoder.Telegram", now: 0)
        #expect(schedule.mayPhotograph(bundleID: "com.caldis.Mos", now: 1))
    }

    @Test("An application that came away with no image is tried again sooner")
    func retriedWhenNothingWasStored() {
        var schedule = PhotoSchedule27()
        schedule.recordAttempt(bundleID: "ru.keepcoder.Telegram", now: 0, stored: false)
        #expect(!schedule.mayPhotograph(bundleID: "ru.keepcoder.Telegram", now: 44))
        #expect(schedule.mayPhotograph(bundleID: "ru.keepcoder.Telegram", now: 45))
    }
}

@Suite("ItemClick27")
struct ItemClick27Tests {
    @Test("No activation when the Ice Bar is on the active menu bar's display")
    func sameDisplay() {
        #expect(!ItemClick27.needsMenuBarActivation(activeDisplayID: 3, iceBarDisplayID: 3))
    }

    @Test("Activation when the Ice Bar is on another display")
    func otherDisplay() {
        #expect(ItemClick27.needsMenuBarActivation(activeDisplayID: 3, iceBarDisplayID: 1))
    }

    @Test("No activation without a known Ice Bar display")
    func unknownDisplay() {
        #expect(!ItemClick27.needsMenuBarActivation(activeDisplayID: 3, iceBarDisplayID: nil))
    }

    @Test("A new window of the item's process means its interface is open")
    func interfaceOpen() {
        let windows = [(number: 10, ownerPID: Int32(100)), (number: 42, ownerPID: Int32(555))]
        #expect(ItemClick27.interfaceIsOpen(windowOwners: windows, ownerPID: 555, baseline: [10]))
    }

    @Test("Windows that were already there, or belong to others, do not count")
    func interfaceClosed() {
        let windows = [(number: 10, ownerPID: Int32(555)), (number: 42, ownerPID: Int32(100))]
        #expect(!ItemClick27.interfaceIsOpen(windowOwners: windows, ownerPID: 555, baseline: [10]))
    }
}

@Suite("Item image background")
struct ItemImageBackground27Tests {
    /// A 5×5 tile of `background` with `centre` in the middle and an optional second
    /// pixel at (1, 1), which stands for a soft edge of the glyph.
    func tile(
        background: (r: UInt8, g: UInt8, b: UInt8),
        centre: (r: UInt8, g: UInt8, b: UInt8) = (255, 255, 255),
        edge: (r: UInt8, g: UInt8, b: UInt8)? = nil
    ) -> [UInt8] {
        var pixels = [UInt8]()
        for y in 0..<5 {
            for x in 0..<5 {
                var colour = background
                if x == 2, y == 2 {
                    colour = centre
                } else if x == 1, y == 1, let edge {
                    colour = edge
                }
                pixels += [colour.r, colour.g, colour.b, 255]
            }
        }
        return pixels
    }

    func alpha(_ pixels: [UInt8], x: Int, y: Int) -> UInt8 {
        pixels[(y * 5 + x) * 4 + 3]
    }

    @Test("The background colour is taken from the edges, not the glyph")
    func backgroundFromEdges() {
        let background = ItemImages27.backgroundColor(pixels: tile(background: (100, 140, 170)), width: 5, height: 5)
        #expect(background.r == 100 && background.g == 140 && background.b == 170)
    }

    @Test("Background pixels become transparent and the glyph stays opaque")
    func backgroundRemoved() {
        let pixels = ItemImages27.removingBackground(pixels: tile(background: (100, 140, 170)), width: 5, height: 5, background: (100, 140, 170))
        #expect(alpha(pixels, x: 0, y: 0) == 0)
        #expect(alpha(pixels, x: 2, y: 2) == 255)
    }

    @Test("A background that turns midway down the rows also comes away clean")
    func shadedUnevenlyRemoved() {
        // Measured on macOS 27.0: the wallpaper behind the translucent bar shows through with
        // its own structure, so one column ran 109 to 130 in red and 202 to 166 in blue, with
        // the turn in the middle rows. A background interpolated between the top and bottom
        // rows was out by up to 20 of 255 there, and that residue was the pale box behind
        // every glyph. These are those measured colours, one per row.
        let rows: [(r: UInt8, g: UInt8, b: UInt8)] = [
            (109, 130, 202), (108, 130, 199), (117, 131, 191), (127, 135, 183), (130, 135, 177),
        ]
        var pixels = [UInt8]()
        for y in 0..<5 {
            for x in 0..<5 {
                let colour = x == 2 && y == 2 ? (r: UInt8(255), g: UInt8(255), b: UInt8(255)) : rows[y]
                pixels += [colour.r, colour.g, colour.b, 255]
            }
        }
        let cleaned = ItemImages27.removingBackground(pixels: pixels, width: 5, height: 5, background: rows[2])
        for y in 0..<5 {
            for x in 0..<5 where !(x == 2 && y == 2) {
                #expect(alpha(cleaned, x: x, y: y) == 0)
            }
        }
        #expect(alpha(cleaned, x: 2, y: 2) == 255)
    }

    @Test("A photographed wallpaper behind a white glyph does not come through")
    func texturedBackgroundRemoved() {
        // Measured on macOS 27.0 over an aerial photograph: road, cars and markings changed the
        // bar's colour within a single item's width, so no guess at the background held and the
        // photograph came through as part of the glyph. Mid-tones like these must not.
        let width = 12
        let height = 8
        func isGlyph(_ x: Int, _ y: Int) -> Bool {
            (4...7).contains(x) && (2...4).contains(y)
        }
        var pixels = [UInt8]()
        for y in 0..<height {
            for x in 0..<width {
                let shade = UInt8(100 + (x * 37 + y * 23) % 61)
                let value: UInt8 = isGlyph(x, y) ? 255 : shade
                pixels += [value, value, value, 255]
            }
        }
        let background = ItemImages27.backgroundColor(pixels: pixels, width: width, height: height)
        let result = ItemImages27.removingBackground(pixels: pixels, width: width, height: height, background: background)
        for y in 0..<height {
            for x in 0..<width {
                let alpha = result[(y * width + x) * 4 + 3]
                if isGlyph(x, y) {
                    #expect(alpha > 200)
                } else {
                    #expect(alpha == 0)
                }
            }
        }
    }

    @Test("A bar's glyph tone wins over a dark patch that outnumbers the glyph in one tile")
    func toneFromTheWholeBar() {
        // Measured on macOS 27.0: the battery sat on a patch of dark asphalt, its own tile
        // judged the glyph black, and it came out as a black box with the battery cut out of it.
        // Here the near-black patch outnumbers the white glyph, as it did there.
        let width = 12
        let height = 6
        func isGlyph(_ x: Int, _ y: Int) -> Bool {
            (8...9).contains(x) && (2...3).contains(y)
        }
        func isPatch(_ x: Int, _ y: Int) -> Bool {
            (1...5).contains(x) && (1...4).contains(y)
        }
        var pixels = [UInt8]()
        for y in 0..<height {
            for x in 0..<width {
                let value: UInt8 = isGlyph(x, y) ? 255 : isPatch(x, y) ? 10 : 128
                pixels += [value, value, value, 255]
            }
        }
        let background = ItemImages27.backgroundColor(pixels: pixels, width: width, height: height)
        let result = ItemImages27.removingBackground(
            pixels: pixels, width: width, height: height, background: background, tone: .light
        )
        for y in 0..<height {
            for x in 0..<width {
                let alpha = result[(y * width + x) * 4 + 3]
                if isGlyph(x, y) {
                    #expect(alpha > 200)
                } else {
                    #expect(alpha == 0)
                }
            }
        }
        let votes = ItemImages27.toneVotes(pixels: pixels, width: width, height: height)
        #expect(votes.light == 4)
    }

    @Test("The glyph keeps its own colour")
    func glyphColourKept() {
        let pixels = ItemImages27.removingBackground(pixels: tile(background: (100, 140, 170), centre: (40, 200, 90)), width: 5, height: 5, background: (100, 140, 170))
        let offset = (2 * 5 + 2) * 4
        #expect(pixels[offset] == 40 && pixels[offset + 1] == 200 && pixels[offset + 2] == 90)
    }

    @Test("A pixel halfway between the glyph and the background is half opaque")
    func halfBlendIsHalfOpaque() {
        // Glyph (20, 20, 20) on background (100, 140, 170); the edge pixel is their mix.
        let pixels = ItemImages27.removingBackground(
            pixels: tile(background: (100, 140, 170), centre: (20, 20, 20), edge: (60, 80, 95)),
            width: 5,
            height: 5,
            background: (100, 140, 170)
        )
        #expect(alpha(pixels, x: 2, y: 2) == 255)
        let edge = Int(alpha(pixels, x: 1, y: 1))
        #expect(edge > 112 && edge < 143)
    }

    @Test("A glyph the colour of the bar's text stays fully opaque")
    func faintGlyphStaysOpaque() {
        // A dark grey glyph on a light bar: far less contrast, still the glyph.
        let pixels = ItemImages27.removingBackground(
            pixels: tile(background: (157, 194, 218), centre: (120, 150, 170)),
            width: 5,
            height: 5,
            background: (157, 194, 218)
        )
        #expect(alpha(pixels, x: 2, y: 2) == 255)
    }

    @Test("Beside a strong glyph, a pixel close to the background stays faint")
    func edgesFade() {
        // Opacity is a share of the glyph's own contrast, so the same edge colour means
        // different opacity depending on how strong the glyph beside it is.
        let pixels = ItemImages27.removingBackground(
            pixels: tile(background: (100, 140, 170), centre: (255, 255, 255), edge: (130, 140, 170)),
            width: 5,
            height: 5,
            background: (100, 140, 170)
        )
        let a = Int(alpha(pixels, x: 1, y: 1))
        #expect(a > 0 && a < 80)
    }

    @Test("A bar whose colour drifts across the item still disappears completely")
    func driftingBackgroundRemoved() {
        // The menu bar is translucent, so the wallpaper behind it makes its colour drift
        // from one side of an item to the other. Subtracting a single colour leaves a
        // haze over the whole tile, which shows as a pale box behind the glyph.
        let width = 7
        let height = 6
        var pixels = [UInt8]()
        for y in 0..<height {
            for x in 0..<width {
                let drift = UInt8(5 * x)
                var colour: (r: UInt8, g: UInt8, b: UInt8) = (100 + drift, 140 + drift, 170 + drift)
                if x == 3, (2...3).contains(y) {
                    colour = (20, 20, 20)
                }
                pixels += [colour.r, colour.g, colour.b, 255]
            }
        }
        let background = ItemImages27.backgroundColor(pixels: pixels, width: width, height: height)
        let result = ItemImages27.removingBackground(pixels: pixels, width: width, height: height, background: background)
        for y in 0..<height {
            for x in 0..<width where !(x == 3 && (2...3).contains(y)) {
                #expect(result[(y * width + x) * 4 + 3] == 0)
            }
        }
        #expect(result[(2 * width + 3) * 4 + 3] == 255)
    }

    @Test("A bar that shades from its top to its bottom also disappears completely")
    func shadedBackgroundRemoved() {
        // Measured on macOS 27.0: the bar's colour drifts by 11–18 between its top and
        // bottom rows, so a background taken from one row leaves a haze on the other.
        let width = 6
        let height = 8
        var pixels = [UInt8]()
        for y in 0..<height {
            for x in 0..<width {
                let shade = UInt8(2 * y)
                var colour: (r: UInt8, g: UInt8, b: UInt8) = (100 + shade, 140 + shade, 170 + shade)
                if x == 3, (3...4).contains(y) {
                    colour = (20, 20, 20)
                }
                pixels += [colour.r, colour.g, colour.b, 255]
            }
        }
        let background = ItemImages27.backgroundColor(pixels: pixels, width: width, height: height)
        let result = ItemImages27.removingBackground(pixels: pixels, width: width, height: height, background: background)
        for y in 0..<height {
            for x in 0..<width where !(x == 3 && (3...4).contains(y)) {
                #expect(result[(y * width + x) * 4 + 3] == 0)
            }
        }
        // The shading makes the lower of the two glyph pixels the furthest from the bar, so
        // it is the one that sets full opacity; the other is a hair behind it.
        #expect(result[(4 * width + 3) * 4 + 3] == 255)
        #expect(result[(3 * width + 3) * 4 + 3] >= 250)
    }

    @Test("A recoloured glyph keeps its shape")
    func tintedKeepsShape() {
        let keyed = ItemImages27.removingBackground(
            pixels: tile(background: (100, 140, 170), centre: (255, 255, 255), edge: (178, 198, 213)),
            width: 5,
            height: 5,
            background: (100, 140, 170)
        )
        let tinted = ItemImages27.tinted(pixels: keyed, colour: (10, 10, 10))
        let centre = (2 * 5 + 2) * 4
        let edge = (1 * 5 + 1) * 4
        #expect(tinted[centre] == 10 && tinted[centre + 1] == 10 && tinted[centre + 2] == 10)
        #expect(tinted[centre + 3] == 255)
        #expect(tinted[edge + 3] == keyed[edge + 3])
        #expect(tinted[edge + 3] > 0 && tinted[edge + 3] < 255)
    }
}

@Suite("System item panel")
struct SystemPanel27Tests {
    // Measured on macOS 27.0: pressing Control Centre through Accessibility opens
    // "Control Center", layer 101, 656×964, after about 177 ms.
    let before: Set<Int> = [10, 11]

    @Test("A new tall window above the menu bar means the panel opened")
    func opened() {
        let after: [(number: Int, layer: Int, height: CGFloat)] = [(number: 10, layer: 20, height: 1080.0), (number: 42, layer: 101, height: 964.0)]
        #expect(ItemClick27.panelOpened(before: before, windows: after))
    }

    @Test("The windows that were already there do not count")
    func nothingNew() {
        let after: [(number: Int, layer: Int, height: CGFloat)] = [(number: 10, layer: 20, height: 1080.0), (number: 11, layer: 101, height: 964.0)]
        #expect(!ItemClick27.panelOpened(before: before, windows: after))
    }

    @Test("A small new window is not a panel")
    func tooSmall() {
        let after: [(number: Int, layer: Int, height: CGFloat)] = [(number: 43, layer: 101, height: 28.0)]
        #expect(!ItemClick27.panelOpened(before: before, windows: after))
    }

    @Test("An ordinary window opening at the same moment is not a panel")
    func ordinaryWindow() {
        let after: [(number: Int, layer: Int, height: CGFloat)] = [(number: 44, layer: 0, height: 700.0)]
        #expect(!ItemClick27.panelOpened(before: before, windows: after))
    }

    // Measured on macOS 27.0: the clock opens "Notification Center", layer 21, the size of
    // the display, about 166 ms after the click. It stands far below Control Centre's level.
    @Test("Notification Center counts, low as its window stands")
    func notificationCenter() {
        let after: [(number: Int, layer: Int, height: CGFloat)] = [(number: 45, layer: 21, height: 1080.0)]
        #expect(ItemClick27.panelWindow(before: before, windows: after) == 45)
    }

    @Test("A panel already on screen is the one a click would close")
    func alreadyOpen() {
        let withPanel: [(number: Int, layer: Int, height: CGFloat)] = [
            (number: 10, layer: 0, height: 900.0),
            (number: 45, layer: 21, height: 1080.0),
        ]
        let withoutPanel: [(number: Int, layer: Int, height: CGFloat)] = [
            (number: 10, layer: 0, height: 900.0),
            (number: 11, layer: 25, height: 38.0),
        ]
        #expect(ItemClick27.openPanelWindow(windows: withPanel) == 45)
        #expect(ItemClick27.openPanelWindow(windows: withoutPanel) == nil)
    }

    @Test("A panel is open while its window is on screen, and closed once it goes")
    func staysOnScreen() {
        let open: [(number: Int, layer: Int, height: CGFloat)] = [(number: 45, layer: 21, height: 1080.0)]
        let closed: [(number: Int, layer: Int, height: CGFloat)] = [(number: 10, layer: 20, height: 1080.0)]
        #expect(ItemClick27.panelIsOnScreen(window: 45, windows: open))
        #expect(!ItemClick27.panelIsOnScreen(window: 45, windows: closed))
    }
}

@Suite("Faded item tiles")
struct FadedTile27Tests {
    /// A tile of the given size holding that many opaque and that many faint pixels.
    func tile(width: Int, height: Int, ink: Int, haze: Int) -> [UInt8] {
        var pixels = [UInt8](repeating: 0, count: width * height * 4)
        var index = 3
        for _ in 0..<ink {
            pixels[index] = 255
            index += 4
        }
        for _ in 0..<haze {
            pixels[index] = 40
            index += 4
        }
        return pixels
    }

    // The proportions below are the ones measured on macOS 27.0; see `ItemImages27.isFaded`.
    @Test("An item photographed standing still is kept")
    func standingStill() {
        let pixels = tile(width: 20, height: 20, ink: 52, haze: 28)
        #expect(!ItemImages27.isFaded(pixels: pixels, width: 20, height: 20))
    }

    @Test("An item caught mid-fade is rejected")
    func midFade() {
        let pixels = tile(width: 20, height: 20, ink: 8, haze: 88)
        #expect(ItemImages27.isFaded(pixels: pixels, width: 20, height: 20))
    }

    @Test("A tile with a little faint ink and no glyph at all is rejected")
    func noGlyph() {
        let pixels = tile(width: 10, height: 10, ink: 0, haze: 4)
        #expect(ItemImages27.isFaded(pixels: pixels, width: 10, height: 10))
    }

    @Test("Three times as much haze as ink is still kept, and four times is not")
    func theBoundary() {
        let atTheLimit = tile(width: 20, height: 20, ink: 20, haze: 60)
        let beyondIt = tile(width: 20, height: 20, ink: 20, haze: 81)
        #expect(!ItemImages27.isFaded(pixels: atTheLimit, width: 20, height: 20))
        #expect(ItemImages27.isFaded(pixels: beyondIt, width: 20, height: 20))
    }

    @Test("A faint mark apart from the glyph is dropped, the glyph's own soft rim is kept")
    func faintMarksDropped() {
        // A solid glyph with a soft rim beside it, and a separate faint streak two columns off:
        // a road marking photographed beside every hidden item (measured on macOS 27.0).
        let width = 10
        let height = 5
        var pixels = [UInt8](repeating: 0, count: width * height * 4)
        func set(_ x: Int, _ y: Int, _ alpha: UInt8) {
            pixels[(y * width + x) * 4 + 3] = alpha
        }
        for y in 1...3 {
            for x in 1...3 {
                set(x, y, 255)
            }
            set(4, y, 60)
        }
        for y in 0..<height {
            set(8, y, 50)
        }
        let result = ItemImages27.droppingFaintMarks(pixels: pixels, width: width, height: height)
        func alpha(_ x: Int, _ y: Int) -> UInt8 {
            result[(y * width + x) * 4 + 3]
        }
        #expect(alpha(2, 2) == 255)
        #expect(alpha(4, 2) == 60)
        for y in 0..<height {
            #expect(alpha(8, y) == 0)
        }
    }
}

@Suite("Items zone")
struct ItemsZone27Tests {
    let bounds = CGRect(x: 0, y: 0, width: 1920, height: 1080)
    let items = [
        ItemHitTest27.Item(frame: CGRect(x: 1400, y: 2, width: 30, height: 24), ownerPID: 11, isOnScreen: true),
        ItemHitTest27.Item(frame: CGRect(x: 1500, y: 2, width: 30, height: 24), ownerPID: 12, isOnScreen: true),
    ]
    let systemFrames = [CGRect(x: 1700, y: 4, width: 26, height: 22)]

    @Test("The gap between two items belongs to the items, not to empty space")
    func gapBelongsToItems() {
        #expect(ItemHitTest27.isInsideItemsArea(
            point: CGPoint(x: 1460, y: 12),
            displayBounds: bounds,
            items: items,
            concealedPIDs: [],
            systemFrames: systemFrames,
            rememberedLeftEdge: nil
        ))
    }

    @Test("The bar left of every item is still empty space")
    func leftOfItemsIsEmpty() {
        #expect(!ItemHitTest27.isInsideItemsArea(
            point: CGPoint(x: 900, y: 12),
            displayBounds: bounds,
            items: items,
            concealedPIDs: [],
            systemFrames: systemFrames,
            rememberedLeftEdge: nil
        ))
    }

    @Test("Frames left behind on the other display do not drag the edge across")
    func otherDisplayIgnored() {
        let stray = ItemHitTest27.Item(frame: CGRect(x: -500, y: 2, width: 30, height: 24), ownerPID: 13, isOnScreen: true)
        #expect(!ItemHitTest27.isInsideItemsArea(
            point: CGPoint(x: 900, y: 12),
            displayBounds: bounds,
            items: items + [stray],
            concealedPIDs: [],
            systemFrames: systemFrames,
            rememberedLeftEdge: nil
        ))
    }

    @Test("Where nothing is drawn, the edge remembered from that display is used")
    func rememberedEdge() {
        #expect(ItemHitTest27.isInsideItemsArea(
            point: CGPoint(x: 1450, y: 12),
            displayBounds: bounds,
            items: [],
            concealedPIDs: [],
            systemFrames: [],
            rememberedLeftEdge: 1400
        ))
    }

    @Test("The remembered edge counts even when items are drawn further right")
    func rememberedWithDrawn() {
        // Ice's cache holds only the items it manages, so the run of the bar can start
        // further left than anything in it.
        #expect(ItemHitTest27.isInsideItemsArea(
            point: CGPoint(x: 1250, y: 12),
            displayBounds: bounds,
            items: items,
            concealedPIDs: [],
            systemFrames: systemFrames,
            rememberedLeftEdge: 1200
        ))
    }

    @Test("With nothing known at all, hovering still works")
    func nothingKnown() {
        #expect(!ItemHitTest27.isInsideItemsArea(
            point: CGPoint(x: 1450, y: 12),
            displayBounds: bounds,
            items: [],
            concealedPIDs: [],
            systemFrames: [],
            rememberedLeftEdge: nil
        ))
    }
}

@Suite("Settled item frames")
struct SettledFrames27Tests {
    let a = CGRect(x: 100, y: 0, width: 30, height: 24)
    let b = CGRect(x: 140, y: 0, width: 30, height: 24)

    @Test("Items that stayed put through the capture are kept")
    func stayedPut() {
        let frames = ["a": a, "b": b]
        #expect(ItemImages27.settledTags(before: frames, after: frames) == ["a", "b"])
    }

    @Test("An item that moved during the capture is dropped")
    func moved() {
        // The bar re-lays out whenever an item is shown or hidden, and a capture taken
        // across that lands between icons, which is how garbled tiles were stored.
        let after = ["a": a.offsetBy(dx: 35, dy: 0), "b": b]
        #expect(ItemImages27.settledTags(before: ["a": a, "b": b], after: after) == ["b"])
    }

    @Test("An item that vanished during the capture is dropped")
    func vanished() {
        #expect(ItemImages27.settledTags(before: ["a": a, "b": b], after: ["b": b]) == ["b"])
    }

    @Test("A sub-point jitter still counts as settled")
    func jitter() {
        let after = ["a": a.offsetBy(dx: 0.5, dy: 0)]
        #expect(ItemImages27.settledTags(before: ["a": a], after: after) == ["a"])
    }
}

@Suite("Item image trimming")
struct ItemImageTrimming27Tests {
    /// A tile `width` wide whose pixels are opaque only in the given columns.
    func tile(width: Int, opaque: Range<Int>) -> [UInt8] {
        var pixels = [UInt8]()
        for _ in 0..<4 {
            for x in 0..<width {
                pixels += [0, 0, 0, opaque.contains(x) ? 255 : 0]
            }
        }
        return pixels
    }

    @Test("The glyph's own columns are found, whatever the margins around it")
    func glyphColumns() {
        let columns = ItemImages27.glyphColumns(pixels: tile(width: 10, opaque: 3..<7), width: 10, height: 4)
        #expect(columns?.lowerBound == 3)
        #expect(columns?.upperBound == 6)
    }

    @Test("A tile with nothing drawn in it has no columns")
    func emptyTile() {
        #expect(ItemImages27.glyphColumns(pixels: tile(width: 10, opaque: 0..<0), width: 10, height: 4) == nil)
    }

    @Test("A nearly transparent edge does not count as the glyph")
    func faintEdgeIgnored() {
        var pixels = tile(width: 10, opaque: 4..<6)
        pixels[(0 * 10 + 1) * 4 + 3] = 8 // a trace of the neighbouring item
        let columns = ItemImages27.glyphColumns(pixels: pixels, width: 10, height: 4)
        #expect(columns?.lowerBound == 4)
    }
}

@Suite("SectionLayoutEditing27")
struct SectionLayoutEditing27Tests {
    let saved: [String: MacOS27Section] = ["ru.keepcoder.Telegram": .hidden, "com.caldis.Mos": .alwaysHidden]

    @Test("Moving an application to a hidden section stores it")
    func toHidden() {
        let updated = SectionLayout27.settingSection(.hidden, for: "com.electron.pritunl", in: saved)
        #expect(updated["com.electron.pritunl"] == .hidden)
        #expect(updated.count == 3)
    }

    @Test("Moving an application to Visible removes it, since missing means visible")
    func toVisible() {
        let updated = SectionLayout27.settingSection(.visible, for: "ru.keepcoder.Telegram", in: saved)
        #expect(updated["ru.keepcoder.Telegram"] == nil)
        #expect(updated["com.caldis.Mos"] == .alwaysHidden)
    }

    @Test("Moving between hidden sections replaces the entry")
    func between() {
        let updated = SectionLayout27.settingSection(.alwaysHidden, for: "ru.keepcoder.Telegram", in: saved)
        #expect(updated["ru.keepcoder.Telegram"] == .alwaysHidden)
    }
}
