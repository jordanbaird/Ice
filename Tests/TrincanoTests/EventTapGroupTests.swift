//
//  EventTapGroupTests.swift
//  TrincanoTests
//

import Foundation
import Testing

/// Lifetime of the taps of an event operation: they must be disabled and
/// released on success, on error and on cancellation, every time.
struct EventTapGroupTests {
    /// A fake tap. Like the real `EventTap`, it retains its callback.
    private final class Tracker {
        var live = 0
    }

    private final class FakeTap {
        private(set) var disableCalls = 0
        let callback: (FakeTap) -> Void
        private let tracker: Tracker

        init(tracker: Tracker, callback: @escaping (FakeTap) -> Void) {
            self.tracker = tracker
            self.callback = callback
            tracker.live += 1
        }

        func disable() { disableCalls += 1 }
        deinit { tracker.live -= 1 }
    }

    enum Ending: String, Sendable {
        case success, error, cancellation
    }

    /// Mimics `postEventWithBarrier`: build taps whose callbacks capture the counter
    /// (never the group), adopt them, and tear down on whichever path ends the operation.
    private func runOperation(ending: Ending, tracker: Tracker) -> [WeakBox] {
        let counter = EventCounter(count: 3)
        let group = EventTapGroup<FakeTap> { $0.disable() }
        defer { group.tearDown() }                       // the real code does this in a `defer`
        let taps = (0..<3).map { _ in FakeTap(tracker: tracker) { _ in counter.count -= 1 } }
        group.adopt(taps)
        switch ending {
        case .success: taps.forEach { $0.callback($0) }
        case .error: break                               // timeout / event creation failure
        case .cancellation: break
        }
        return taps.map(WeakBox.init)
    }

    private final class WeakBox {
        weak var tap: FakeTap?
        init(_ tap: FakeTap) { self.tap = tap }
    }

    @Test(arguments: [Ending.success, .error, .cancellation])
    func tapsAreReleasedAfterEveryKindOfEnding(_ ending: Ending) {
        let tracker = Tracker()
        let boxes = runOperation(ending: ending, tracker: tracker)
        #expect(boxes.allSatisfy { $0.tap == nil }, "taps leaked after \(ending.rawValue)")
        #expect(tracker.live == 0)
    }

    @Test func repeatedOperationsDoNotAccumulateTaps() {
        let tracker = Tracker()
        for index in 0..<200 {
            let ending: Ending = [.success, .error, .cancellation][index % 3]
            _ = runOperation(ending: ending, tracker: tracker)
        }
        #expect(tracker.live == 0, "leaked \(tracker.live) taps")
    }

    @Test func tearDownDisablesEveryTapExactlyOnceAndIsIdempotent() {
        let tracker = Tracker()
        let group = EventTapGroup<FakeTap> { $0.disable() }
        let taps = (0..<3).map { _ in FakeTap(tracker: tracker) { _ in } }
        group.adopt(taps)
        group.tearDown()
        group.tearDown()
        #expect(taps.allSatisfy { $0.disableCalls == 1 })
    }

    @Test func droppingTheGroupTearsItDown() {
        let tracker = Tracker()
        do {
            let group = EventTapGroup<FakeTap> { $0.disable() }
            group.adopt([FakeTap(tracker: tracker) { _ in }])
        }
        #expect(tracker.live == 0)
    }

    @Test func callbacksCaptureOnlyTheCounterSoNoCycleForms() {
        let tracker = Tracker()
        weak var weakGroup: EventTapGroup<FakeTap>?
        do {
            let counter = EventCounter(count: 1)
            let group = EventTapGroup<FakeTap> { $0.disable() }
            weakGroup = group
            group.adopt([FakeTap(tracker: tracker) { _ in counter.count -= 1 }])
            // no tearDown: dropping the last reference must free the group AND its taps
        }
        #expect(weakGroup == nil)
        #expect(tracker.live == 0)
    }

    /// Characterization of the bug this type fixes: a state object that owns the taps
    /// AND is captured by their callbacks forms a cycle (state -> taps -> callbacks -> state)
    /// that nothing breaks, so every operation leaked its taps.
    private final class CyclicState {
        var count: Int
        var taps = [FakeTap]()
        init(count: Int) { self.count = count }
    }

    @Test func theOldSharedStateDesignLeaksWhichIsWhyTheGroupIsSeparate() {
        let tracker = Tracker()
        for _ in 0..<5 {
            let state = CyclicState(count: 2)
            state.taps = (0..<2).map { _ in FakeTap(tracker: tracker) { _ in state.count -= 1 } }
        }
        #expect(tracker.live == 10, "the cycle should have kept all taps alive")
    }
}
