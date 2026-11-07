//
//  EventTapGroupTests.swift
//  TrincanoTests
//

import Foundation
import Testing

/// Lifetime of the taps of an event operation: they must be disabled and
/// released on success, on error and on cancellation, every time.
@MainActor
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
        let group = EventTapGroup<FakeTap>(disable: { $0.disable() })
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
        let group = EventTapGroup<FakeTap>(disable: { $0.disable() })
        let taps = (0..<3).map { _ in FakeTap(tracker: tracker) { _ in } }
        group.adopt(taps)
        group.tearDown()
        group.tearDown()
        #expect(taps.allSatisfy { $0.disableCalls == 1 })
    }

    @Test func callbacksCaptureOnlyTheCounterSoNoCycleForms() {
        let tracker = Tracker()
        weak var weakGroup: EventTapGroup<FakeTap>?
        do {
            let counter = EventCounter(count: 1)
            let group = EventTapGroup<FakeTap>(disable: { $0.disable() })
            weakGroup = group
            group.adopt([FakeTap(tracker: tracker) { _ in counter.count -= 1 }])
            group.tearDown()
            // dropping the last reference must now free the group (no cycle through the callbacks)
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
        var states = [CyclicState]()
        for _ in 0..<5 {
            let state = CyclicState(count: 2)
            state.taps = (0..<2).map { _ in FakeTap(tracker: tracker) { _ in state.count -= 1 } }
            states.append(state)
        }
        states.append(contentsOf: [])
        #expect(tracker.live == 10, "the cycle should have kept all taps alive")
        // Break the cycles again so this characterization doesn't leak into other tests or leak checkers.
        for state in states { state.taps.removeAll() }
        states.removeAll()
        #expect(tracker.live == 0)
    }

    // MARK: Executor: adopt, disable and release happen on the main thread.

    /// Records where each tap was disabled and released.
    private final class ThreadLog: @unchecked Sendable {
        private let lock = NSLock()
        private var disabledOnMain = [Bool]()
        private var releasedOnMain = [Bool]()

        func disabled() { lock.withLock { disabledOnMain.append(Thread.isMainThread) } }
        func released() { lock.withLock { releasedOnMain.append(Thread.isMainThread) } }
        var disableThreads: [Bool] { lock.withLock { disabledOnMain } }
        var releaseThreads: [Bool] { lock.withLock { releasedOnMain } }
    }

    private final class LoggedTap: @unchecked Sendable {
        let log: ThreadLog
        init(log: ThreadLog) { self.log = log }
        deinit { log.released() }
    }

    private struct OperationFailure: Error {}

    enum Behaviour: Sendable { case success, failure, cancellation }

    /// The same shape as the real operation: build taps, adopt them, wait on a real
    /// suspension point, then finish by returning, throwing or being cancelled.
    private nonisolated func operation(_ behaviour: Behaviour, log: ThreadLog) async throws {
        let disableTap: @MainActor (LoggedTap) -> Void = { _ in log.disabled() }
        try await EventTapGroup<LoggedTap>.withGroup(disable: disableTap) { group in
            group.adopt((0..<3).map { _ in LoggedTap(log: log) })
            switch behaviour {
            case .success:
                try await Task.sleep(for: .milliseconds(5))
            case .failure:
                try await Task.sleep(for: .milliseconds(5))
                throw OperationFailure()
            case .cancellation:
                try await Task.sleep(for: .seconds(60))   // cancelled from outside while suspended
            }
        }
    }

    @Test(arguments: [Behaviour.success, .failure, .cancellation])
    func disableAndReleaseHappenOnTheMainThreadEvenWhenStartedFromADetachedTask(_ behaviour: Behaviour) async {
        let log = ThreadLog()
        let task = Task.detached {
            try await self.operation(behaviour, log: log)
        }
        if behaviour == .cancellation {
            try? await Task.sleep(for: .milliseconds(20))
            task.cancel()
        }
        let result = await task.result
        switch (behaviour, result) {
        case (.success, .success): break
        case (.failure, .failure(let error)): #expect(error is OperationFailure)
        case (.cancellation, .failure(let error)): #expect(error is CancellationError)
        default: Issue.record("unexpected result for \(behaviour): \(result)")
        }
        #expect(log.disableThreads == [true, true, true], "disable ran off the main thread: \(log.disableThreads)")
        #expect(log.releaseThreads == [true, true, true], "release ran off the main thread: \(log.releaseThreads)")
    }

    @Test func repeatedDetachedOperationsAllCleanUpOnTheMainThread() async {
        let log = ThreadLog()
        for index in 0..<30 {
            let behaviour: Behaviour = [.success, .failure][index % 2]
            _ = await Task.detached { try? await self.operation(behaviour, log: log) }.result
        }
        #expect(log.disableThreads.count == 90)
        #expect(log.disableThreads.allSatisfy { $0 })
        #expect(log.releaseThreads.allSatisfy { $0 })
    }
}
