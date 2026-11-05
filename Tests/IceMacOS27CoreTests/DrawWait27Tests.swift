import CoreGraphics
import Testing
@testable import IceMacOS27Core

@Suite("DrawWait27")
struct DrawWait27Tests {
    /// Measured on macOS 27.2: the external display is primary, the built-in one sits to its
    /// left, and its notch spans -848 to -664.
    let external = CGRect(x: 0, y: 0, width: 1920, height: 1080)
    let builtIn = CGRect(x: -1512, y: 98, width: 1512, height: 982)
    let notch: ClosedRange<CGFloat> = -848...(-664)

    /// The waits `Concealer27` uses, measured 2026-11-04.
    let floor = Duration.milliseconds(500)
    let foldedVerdict = Duration.milliseconds(900)
    let timeout = Duration.milliseconds(1500)

    /// Below this an item is a sliver rather than something a person can see or click.
    let minimumWidth: CGFloat = 4

    private func input(
        elapsed: Duration,
        drawnFrames: [CGRect] = [],
        undrawnFrames: [CGRect] = [],
        notchXRange: ClosedRange<CGFloat>? = nil,
        activeDisplayBounds: CGRect? = nil,
        hasCollapsedOverflow: Bool = false,
        acrossNotchIsFinal: Bool = true
    ) -> DrawWait27.Input {
        DrawWait27.Input(
            elapsed: elapsed,
            floor: floor,
            timeout: timeout,
            foldedVerdict: foldedVerdict,
            drawnFrames: drawnFrames,
            undrawnFrames: undrawnFrames,
            minimumWidth: minimumWidth,
            notchXRange: notchXRange,
            activeDisplayBounds: activeDisplayBounds,
            hasCollapsedOverflow: hasCollapsedOverflow,
            acrossNotchIsFinal: acrossNotchIsFinal
        )
    }

    @Test("Before the floor nothing is decided")
    func beforeTheFloor() {
        let verdict = DrawWait27.verdict(input(
            elapsed: .milliseconds(300),
            notchXRange: notch,
            activeDisplayBounds: builtIn,
            hasCollapsedOverflow: true
        ))
        #expect(verdict == .keepWaiting)
    }

    @Test("A drawn item ends the wait")
    func drawnEndsTheWait() {
        let frame = CGRect(x: 1404, y: 2, width: 33, height: 24)
        let verdict = DrawWait27.verdict(input(
            elapsed: .milliseconds(600),
            drawnFrames: [frame],
            activeDisplayBounds: external
        ))
        #expect(verdict == .drawn(index: 0))
    }

    @Test("Nothing published and an overflow control on the bar means folded")
    func foldedWhenNothingIsPublished() {
        let verdict = DrawWait27.verdict(input(
            elapsed: .milliseconds(950),
            notchXRange: notch,
            activeDisplayBounds: builtIn,
            hasCollapsedOverflow: true
        ))
        #expect(verdict == .folded)
    }

    @Test("An item across the notch gives up early when that is final")
    func acrossTheNotchIsFinal() {
        let frame = CGRect(x: -690, y: 102, width: 47, height: 24)
        let verdict = DrawWait27.verdict(input(
            elapsed: .milliseconds(600),
            undrawnFrames: [frame],
            notchXRange: notch,
            activeDisplayBounds: builtIn
        ))
        #expect(verdict == .acrossNotch(frame))
    }

    @Test("After an expansion an item across the notch is still worth waiting for")
    func acrossTheNotchAfterAnExpansion() {
        let frame = CGRect(x: -690, y: 102, width: 47, height: 24)
        let verdict = DrawWait27.verdict(input(
            elapsed: .milliseconds(600),
            undrawnFrames: [frame],
            notchXRange: notch,
            activeDisplayBounds: builtIn,
            acrossNotchIsFinal: false
        ))
        #expect(verdict == .keepWaiting)
    }

    @Test("Past the timeout the wait is over")
    func timesOut() {
        let verdict = DrawWait27.verdict(input(
            elapsed: .milliseconds(1600),
            notchXRange: notch,
            activeDisplayBounds: builtIn
        ))
        #expect(verdict == .timedOut)
    }

    /// The caller has to get back the item it asked about, not a frame it then has to find
    /// again: two items of one application can share a frame, and a frame carrying a NaN
    /// cannot be compared with itself at all.
    @Test("The verdict names which drawn frame it chose")
    func drawnNamesItsFrame() {
        let sliver = CGRect(x: 1360, y: 2, width: 3, height: 24)
        let real = CGRect(x: 1404, y: 2, width: 33, height: 24)
        let verdict = DrawWait27.verdict(input(
            elapsed: .milliseconds(600),
            drawnFrames: [sliver, real],
            activeDisplayBounds: external
        ))
        #expect(verdict == .drawn(index: 1))
    }

    /// An item published at a sliver's width is published all the same, so the bar is not
    /// hiding it in its overflow and expanding that would not help. Ice keeps waiting.
    @Test("An item published too narrow to be drawn is not folded away")
    func aSliverIsNotFolded() {
        let verdict = DrawWait27.verdict(input(
            elapsed: .milliseconds(950),
            undrawnFrames: [CGRect(x: -700, y: 102, width: 3, height: 24)],
            notchXRange: notch,
            activeDisplayBounds: builtIn,
            hasCollapsedOverflow: true
        ))
        #expect(verdict == .keepWaiting)
    }

    /// Review Focus 2.
    @Test("A display with no notch never reports an item across it")
    func noNotchNeverReportsAcrossIt() {
        let verdict = DrawWait27.verdict(input(
            elapsed: .milliseconds(600),
            undrawnFrames: [CGRect(x: 24, y: 2, width: 33, height: 24)],
            notchXRange: nil,
            activeDisplayBounds: external
        ))
        #expect(verdict == .keepWaiting)
    }

    /// Review Focus 3. Measured 2026-11-04: after the overflow was expanded the item was
    /// drawn at x=-915 while the bar still had an overflow control of its own.
    @Test("An overflow control on the bar does not make a drawn item folded")
    func drawnBeatsTheOverflowControl() {
        let frame = CGRect(x: -915, y: 102, width: 47, height: 24)
        let verdict = DrawWait27.verdict(input(
            elapsed: .milliseconds(950),
            drawnFrames: [frame],
            notchXRange: notch,
            activeDisplayBounds: builtIn,
            hasCollapsedOverflow: true
        ))
        #expect(verdict == .drawn(index: 0))
    }
}
