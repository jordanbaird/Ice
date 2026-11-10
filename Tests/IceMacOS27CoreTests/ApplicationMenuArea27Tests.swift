import CoreGraphics
import Testing
@testable import IceMacOS27Core

@Suite("ApplicationMenuArea27")
struct ApplicationMenuArea27Tests {
    // The displays this was measured on: an external one at the origin, a notched built-in one
    // to its left, at negative coordinates.
    let external = CGRect(x: 0, y: 0, width: 1920, height: 1080)
    let builtIn = CGRect(x: -1512, y: 98, width: 1512, height: 982)

    @Test("On the display the menus are drawn on, the area runs from its left edge to their end")
    func ownDisplay() {
        // Safari's menus, measured on the external bar: 10 to 572.
        let area = ApplicationMenuArea27.area(
            menuFrame: CGRect(x: 10, y: 0, width: 562, height: 30),
            ownerDisplay: external,
            display: external,
            barHeight: 30
        )
        #expect(area == CGRect(x: 0, y: 0, width: 572, height: 30))
    }

    @Test("The same reach is taken from the other display's own left edge")
    func otherDisplay() {
        let area = ApplicationMenuArea27.area(
            menuFrame: CGRect(x: 10, y: 0, width: 562, height: 30),
            ownerDisplay: external,
            display: builtIn,
            barHeight: 30
        )
        #expect(area == CGRect(x: -1512, y: 98, width: 572, height: 30))
    }

    @Test("The area takes the bar's own top, not the menus' display's")
    func ownTop() {
        // The built-in display here starts 98 points down in the global coordinates, so an area
        // carrying its y contains nothing on the external bar — which is what let a hover over
        // the menus through.
        let area = ApplicationMenuArea27.area(
            menuFrame: CGRect(x: -1502, y: 98, width: 386, height: 33),
            ownerDisplay: builtIn,
            display: external,
            barHeight: 30
        )
        #expect(area == CGRect(x: 0, y: 0, width: 396, height: 30))
        #expect(area.contains(CGPoint(x: 236, y: 26)))
    }

    @Test("Menus owned by the display at negative coordinates still reach from the other's left edge")
    func ownerToTheLeft() {
        // The case that revealed the hidden items: the built-in bar is the active one, so the
        // menus are measured at negative coordinates, and the old arithmetic made the external
        // display's area a rect of negative width, which contains nothing.
        let area = ApplicationMenuArea27.area(
            menuFrame: CGRect(x: -1502, y: 0, width: 562, height: 30),
            ownerDisplay: builtIn,
            display: external,
            barHeight: 30
        )
        #expect(area == CGRect(x: 0, y: 0, width: 572, height: 30))
    }

    @Test("A notch the other display does not have comes off the reach")
    func notchGap() {
        let area = ApplicationMenuArea27.area(
            menuFrame: CGRect(x: -1502, y: 0, width: 900, height: 30),
            ownerDisplay: builtIn,
            display: external,
            barHeight: 30,
            notchGap: 160
        )
        #expect(area.width == 750)
    }

    @Test("The area never leaves the display it is asked about")
    func staysOnTheDisplay() {
        let area = ApplicationMenuArea27.area(
            menuFrame: CGRect(x: -1502, y: 0, width: 4000, height: 30),
            ownerDisplay: builtIn,
            display: external,
            barHeight: 30
        )
        #expect(area.width == external.width)
        #expect(area.minX == external.minX)
    }

    @Test("Menus that measure as nothing take up nothing")
    func nothing() {
        let area = ApplicationMenuArea27.area(
            menuFrame: CGRect(x: -1512, y: 0, width: 0, height: 30),
            ownerDisplay: builtIn,
            display: external,
            barHeight: 30
        )
        #expect(area.width == 0)
    }
}

@Suite("ApplicationMenuArea27, on a display whose menus cannot be measured")
struct ApplicationMenuAreaOtherDisplay27Tests {
    let external = CGRect(x: 0, y: 0, width: 1920, height: 1080)
    let builtIn = CGRect(x: -1512, y: 98, width: 1512, height: 982)

    @Test("Half the way to the first item counts as menus")
    func halfWay() {
        // Measured on 2026-10-08: the menus read 396 wide from the active display, while the
        // external display was drawing another application's, which reach past 590.
        let area = ApplicationMenuArea27.area(
            menuFrame: CGRect(x: -1502, y: 98, width: 386, height: 33),
            ownerDisplay: builtIn,
            display: external,
            barHeight: 30,
            itemsLeftEdge: 1400
        )
        #expect(area.width == 700)
        #expect(area.contains(CGPoint(x: 589, y: 12)))
        #expect(!area.contains(CGPoint(x: 900, y: 12)))
    }

    @Test("Menus longer than half the way keep their own measurement")
    func longMenus() {
        let area = ApplicationMenuArea27.area(
            menuFrame: CGRect(x: -512, y: 98, width: 900, height: 33),
            ownerDisplay: builtIn,
            display: external,
            barHeight: 30,
            itemsLeftEdge: 1400
        )
        #expect(area.width == 1900)
    }

    @Test("With no item to measure against, only the menus count")
    func noItems() {
        let area = ApplicationMenuArea27.area(
            menuFrame: CGRect(x: -1502, y: 98, width: 386, height: 33),
            ownerDisplay: builtIn,
            display: external,
            barHeight: 30
        )
        #expect(area.width == 396)
    }
}

@Suite("ApplicationMenuArea27, remembering what a display's menus measured")
struct ApplicationMenuAreaRemembered27Tests {
    let external = CGRect(x: 0, y: 0, width: 1920, height: 1080)
    let builtIn = CGRect(x: -1512, y: 98, width: 1512, height: 982)

    @Test("A remembered measurement is used instead of halves")
    func remembered() {
        // Safari's menus, measured while it was the active application on the external display:
        // they end at 572. The active display meanwhile reports Slack's, 396 wide.
        let area = ApplicationMenuArea27.area(
            menuFrame: CGRect(x: -1502, y: 98, width: 386, height: 33),
            ownerDisplay: builtIn,
            display: external,
            barHeight: 30,
            itemsLeftEdge: 1400,
            rememberedReach: 572
        )
        #expect(area.width == 572)
        #expect(area.contains(CGPoint(x: 560, y: 12)))
        #expect(!area.contains(CGPoint(x: 600, y: 12)))
    }

    @Test("Halves are only the fallback")
    func fallback() {
        let area = ApplicationMenuArea27.area(
            menuFrame: CGRect(x: -1502, y: 98, width: 386, height: 33),
            ownerDisplay: builtIn,
            display: external,
            barHeight: 30,
            itemsLeftEdge: 1400,
            rememberedReach: nil
        )
        #expect(area.width == 700)
    }
}

@Suite("ApplicationMenuArea27, choosing a measurement")
struct ApplicationMenuAreaReach27Tests {
    @Test("The display's own measurement wins")
    func ownDisplay() {
        #expect(ApplicationMenuArea27.reach(onThisDisplay: 572, onOtherDisplays: [440, 700]) == 572)
    }

    @Test("Without one, the widest the application measured elsewhere is taken")
    func elsewhere() {
        // A bar beside a notch compresses the titles, so the widest reading is the safer one.
        #expect(ApplicationMenuArea27.reach(onThisDisplay: nil, onOtherDisplays: [440, 572]) == 572)
    }

    @Test("With nothing measured at all there is no answer")
    func nothing() {
        #expect(ApplicationMenuArea27.reach(onThisDisplay: nil, onOtherDisplays: []) == nil)
    }
}
