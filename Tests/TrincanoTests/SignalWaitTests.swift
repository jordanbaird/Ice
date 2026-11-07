//
//  SignalWaitTests.swift
//  TrincanoTests
//

import Foundation
import Testing

/// The real wiring: `SignalWait.wait` inside `EventTapGroup.withGroup`, with a fake
/// tap/poster that NEVER sends the return event. The wait must end by itself (timeout
/// or caller cancellation), the group must tear the taps down, and the continuation
/// must be resumed exactly once.
@MainActor
struct SignalWaitTests {
    // Everything touching the tracker happens on the main actor in these tests.
    private final class Tracker: @unchecked Sendable { nonisolated(unsafe) var live = 0 }

    private final class FakeTap: @unchecked Sendable {
        let tracker: Tracker
        private(set) var disabled = false
        init(tracker: Tracker) { self.tracker = tracker; tracker.live += 1 }
        func disable() { disabled = true }
        deinit { tracker.live -= 1 }
    }

    private enum Outcome: Equatable { case finished(String), hung }

    /// Runs `operation`; reports `.hung` if it does not finish within `limit`
    /// (so a regression shows up as a failed expectation instead of a stuck suite).
    private func finishes(within limit: Duration, _ operation: @escaping @Sendable () async -> String) async -> Outcome {
        // Unstructured tasks on purpose: a hung operation (an unresumed continuation) can
        // never finish, and a task group would wait for it forever.
        await withCheckedContinuation { (continuation: CheckedContinuation<Outcome, Never>) in
            let once = Once(continuation)
            Task { once.resume(.finished(await operation())) }
            Task {
                try? await Task.sleep(for: limit)
                once.resume(.hung)
            }
        }
    }

    private final class Once: @unchecked Sendable {
        private let lock = NSLock()
        private var continuation: CheckedContinuation<Outcome, Never>?
        init(_ continuation: CheckedContinuation<Outcome, Never>) { self.continuation = continuation }
        func resume(_ outcome: Outcome) {
            let taken = lock.withLock { () -> CheckedContinuation<Outcome, Never>? in
                defer { continuation = nil }
                return continuation
            }
            taken?.resume(returning: outcome)
        }
    }

    /// The same shape as `postEventWithBarrier`: group + wait, a poster that posts and
    /// then waits for an event that never arrives.
    private func barrier(timeout: Duration, tracker: Tracker, signal: ((@escaping SignalWait.Completion) -> Void)? = nil) async -> String {
        let disable: @MainActor (FakeTap) -> Void = { $0.disable() }
        do {
            try await EventTapGroup<FakeTap>.withGroup(disable: disable) { group in
                try await SignalWait.wait(timeout: timeout) { complete in
                    group.adopt([FakeTap(tracker: tracker), FakeTap(tracker: tracker)])
                    signal?(complete)
                    // "post the event": nothing ever comes back unless `signal` completes it
                }
            }
            return "completed"
        } catch is TaskTimeoutError {
            return "timeout"
        } catch is CancellationError {
            return "cancelled"
        } catch {
            return "error"
        }
    }

    @Test func missingReturnEventEndsWithTimeoutAndCleansUp() async {
        let tracker = Tracker()
        let outcome = await finishes(within: .seconds(3)) { await self.barrier(timeout: .milliseconds(50), tracker: tracker) }
        #expect(outcome == .finished("timeout"), "\(outcome)")
        #expect(tracker.live == 0, "taps leaked after a timeout")
    }

    @Test func cancellingTheCallerEndsTheWaitAndCleansUp() async {
        let tracker = Tracker()
        let outcome = await finishes(within: .seconds(3)) {
            let task = Task { await self.barrier(timeout: .seconds(60), tracker: tracker) }
            try? await Task.sleep(for: .milliseconds(30))
            task.cancel()
            return await task.value
        }
        #expect(outcome == .finished("cancelled"), "\(outcome)")
        #expect(tracker.live == 0, "taps leaked after caller cancellation")
    }

    @Test func cancellingBeforeTheWaitStartsStillEndsAndCleansUp() async {
        let tracker = Tracker()
        let outcome = await finishes(within: .seconds(3)) {
            let task = Task {
                try? await Task.sleep(for: .milliseconds(10))   // already cancelled when it gets here
                return await self.barrier(timeout: .seconds(60), tracker: tracker)
            }
            task.cancel()
            return await task.value
        }
        #expect(outcome == .finished("cancelled"), "\(outcome)")
        #expect(tracker.live == 0)
    }

    @Test func theReturnEventCompletesTheWaitAndCleansUp() async {
        let tracker = Tracker()
        let outcome = await finishes(within: .seconds(3)) {
            await self.barrier(timeout: .seconds(60), tracker: tracker) { complete in
                Task { @MainActor in complete(.success(())) }
            }
        }
        #expect(outcome == .finished("completed"), "\(outcome)")
        #expect(tracker.live == 0)
    }

    @Test func completionIsExactlyOnceEvenWhenSignalledManyTimesAndAfterTheTimeout() async {
        // A checked continuation traps on a second resume, so reaching the expectations is the proof.
        let tracker = Tracker()
        let late = LateSignal()
        let outcome = await finishes(within: .seconds(3)) {
            await self.barrier(timeout: .milliseconds(40), tracker: tracker) { complete in
                late.complete = complete
                complete(.success(()))
                complete(.success(()))
                complete(.failure(CancellationError()))
            }
        }
        #expect(outcome == .finished("completed"))
        late.complete?(.success(()))        // after the wait is over
        late.complete?(.failure(TaskTimeoutError()))
        #expect(tracker.live == 0)
    }

    private final class LateSignal: @unchecked Sendable {
        var complete: SignalWait.Completion?
    }

    @Test func repeatedTimeoutsAndCancellationsDoNotAccumulateTaps() async {
        let tracker = Tracker()
        for index in 0..<20 {
            if index.isMultiple(of: 2) {
                _ = await finishes(within: .seconds(3)) { await self.barrier(timeout: .milliseconds(10), tracker: tracker) }
            } else {
                _ = await finishes(within: .seconds(3)) {
                    let task = Task { await self.barrier(timeout: .seconds(60), tracker: tracker) }
                    try? await Task.sleep(for: .milliseconds(5))
                    task.cancel()
                    return await task.value
                }
            }
        }
        #expect(tracker.live == 0, "leaked \(tracker.live) taps")
    }
}
