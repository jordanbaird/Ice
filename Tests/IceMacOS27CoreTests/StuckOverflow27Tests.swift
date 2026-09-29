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
