import CoreGraphics
import Testing
@testable import IceMacOS27Core

@Suite("StuckOverflow27")
struct StuckOverflow27Tests {
    // Measured on macOS 27.0: a 14-inch built-in display, 790 points unobscured on each side.
    let display = CGRect(x: 0, y: 0, width: 1800, height: 1169)
    var notch: ClosedRange<CGFloat>? {
        StuckOverflow27.notchSpan(displayBounds: display, leftAreaWidth: 790, rightAreaWidth: 790)
    }

    @Test("The notch spans the part of the bar between the unobscured areas")
    func span() {
        #expect(notch == 790...1010)
        #expect(StuckOverflow27.notchSpan(displayBounds: display, leftAreaWidth: nil, rightAreaWidth: nil) == nil)
    }

    @Test("Items laid out side by side are not stuck")
    func laidOut() {
        // Measured on macOS 27.0: neighbours overlap by 2 points.
        let frames = [
            CGRect(x: 1242, y: 7.5, width: 34, height: 24),
            CGRect(x: 1274, y: 7.5, width: 34, height: 24),
            CGRect(x: 1306, y: 7.5, width: 34, height: 24),
            CGRect(x: 1338, y: 7.5, width: 38, height: 24),
            CGRect(x: 1374, y: 7.5, width: 34, height: 24),
        ]
        #expect(!StuckOverflow27.isStuck(visibleItemFrames: frames, chevronFrame: nil, notchSpan: notch))
    }

    @Test("Items stacked on one another with no overflow button are stuck")
    func stacked() {
        let frames = [
            CGRect(x: 1020, y: 2, width: 30, height: 24),
            CGRect(x: 1022, y: 2, width: 30, height: 24),
            CGRect(x: 1400, y: 2, width: 30, height: 24),
        ]
        #expect(StuckOverflow27.isStuck(visibleItemFrames: frames, chevronFrame: nil, notchSpan: notch))
    }

    @Test("An item under the notch with no overflow button is stuck")
    func underNotch() {
        let frames = [CGRect(x: 980, y: 2, width: 30, height: 24), CGRect(x: 1400, y: 2, width: 30, height: 24)]
        #expect(StuckOverflow27.isStuck(visibleItemFrames: frames, chevronFrame: nil, notchSpan: notch))
    }

    @Test("Folded items are expected while the overflow button is there")
    func withChevron() {
        let frames = [CGRect(x: 1020, y: 2, width: 30, height: 24), CGRect(x: 1022, y: 2, width: 30, height: 24)]
        let chevron = CGRect(x: 1030, y: 2, width: 17, height: 30)
        #expect(!StuckOverflow27.isStuck(visibleItemFrames: frames, chevronFrame: chevron, notchSpan: notch))
    }

    @Test("A display without a notch is never stuck")
    func noNotch() {
        let frames = [CGRect(x: 1020, y: 2, width: 30, height: 24), CGRect(x: 1022, y: 2, width: 30, height: 24)]
        #expect(!StuckOverflow27.isStuck(visibleItemFrames: frames, chevronFrame: nil, notchSpan: nil))
    }

    @Test("Ice's collapsed items do not count")
    func collapsed() {
        let frames = [CGRect(x: 1400, y: 2, width: 0, height: 24), CGRect(x: 1400, y: 2, width: 30, height: 24)]
        #expect(!StuckOverflow27.isStuck(visibleItemFrames: frames, chevronFrame: nil, notchSpan: notch))
    }
}

@Suite("Stuck overflow on a bar that is not active")
struct StuckOverflowByCount27Tests {
    // The built-in bar as measured on 2026-10-02, with three Stats modules folded away:
    // one application item and the four system ones.
    let systemFrames = [
        CGRect(x: -238, y: 98, width: 26, height: 33),
        CGRect(x: -196, y: 98, width: 22, height: 33),
        CGRect(x: -158, y: 98, width: 26, height: 33),
        CGRect(x: -116, y: 98, width: 96, height: 33),
    ]

    func item(_ x: CGFloat, _ width: CGFloat) -> CGRect {
        CGRect(x: x, y: 102, width: width, height: 24)
    }

    @Test("Only the entries left of the system group are counted")
    func countsApplicationItems() {
        let count = StuckOverflow27.applicationEntryCount(
            childFrames: [item(-469, 33), item(-422, 33), item(-375, 33), item(-336, 46), item(-284, 31)] + systemFrames,
            systemItemFrames: systemFrames
        )
        #expect(count == 5)
    }

    @Test("Items listed without geometry are counted too")
    func countsPlaceholders() {
        // The bar of the display that is not the active one lists its items this way.
        let count = StuckOverflow27.applicationEntryCount(
            childFrames: [.zero, .zero, .zero, .zero, .zero] + systemFrames,
            systemItemFrames: systemFrames
        )
        #expect(count == 5)
    }

    @Test("A bar missing items counts fewer of them")
    func countsWhatIsLeft() {
        let count = StuckOverflow27.applicationEntryCount(
            childFrames: [item(-284, 31)] + systemFrames,
            systemItemFrames: systemFrames
        )
        #expect(count == 1)
    }

    @Test("A bar drawing fewer items than there are is stuck")
    func fewerThanExpected() {
        #expect(StuckOverflow27.isStuck(drawnApplicationItems: 1, expectedApplicationItems: 5))
    }

    @Test("A bar drawing them all is not")
    func allDrawn() {
        #expect(!StuckOverflow27.isStuck(drawnApplicationItems: 5, expectedApplicationItems: 5))
        #expect(!StuckOverflow27.isStuck(drawnApplicationItems: 6, expectedApplicationItems: 5))
    }

    @Test("With nothing to draw there is nothing to miss")
    func nothingExpected() {
        #expect(!StuckOverflow27.isStuck(drawnApplicationItems: 0, expectedApplicationItems: 0))
    }
}
