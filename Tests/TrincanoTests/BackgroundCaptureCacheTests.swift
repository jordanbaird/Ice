//
//  BackgroundCaptureCacheTests.swift
//  TrincanoTests
//

import Foundation
import os
import Testing

struct BackgroundCaptureCacheTests {
    /// A provider the test completes by hand, simulating a stuck or slow capture.
    ///
    /// `deliver` ends the *result* (UI keeps the previous value); `finish`
    /// ends the *physical work*. A provider that ignores cancellation delivers
    /// a timeout result long before it finishes.
    /// A clock the test advances by hand.
    private final class ManualClock: Sendable {
        private let storage = OSAllocatedUnfairLock(initialState: TimeInterval(0))
        var now: TimeInterval {
            get { storage.withLock { $0 } }
            set { storage.withLock { $0 = newValue } }
        }
    }

    // @unchecked Sendable: each test drives its provider from a single thread.
    private final class ManualProvider: @unchecked Sendable {
        struct Started {
            let key: Int
            let operation: BackgroundCaptureOperation<String>
            /// Delivers the result and ends the work.
            func complete(_ value: String?) {
                operation.deliver(value)
                operation.finish()
            }
            /// Expires the result but leaves the work running (ignores cancellation).
            func expire() { operation.deliver(nil) }
            func finish() { operation.finish() }
        }
        var starts = [Started]()
        func start(_ key: Int, _ operation: BackgroundCaptureOperation<String>) {
            starts.append(Started(key: key, operation: operation))
        }
    }

    private func make(
        provider: ManualProvider,
        maxInFlight: Int = 1,
        clock: @escaping @Sendable () -> TimeInterval = { 0 }
    ) -> BackgroundCaptureCache<Int, String> {
        BackgroundCaptureCache(maxInFlight: maxInFlight, maxAge: 1, now: clock, start: provider.start)
    }

    @Test func stuckProviderNeverBlocksAndIsStartedOnce() {
        let provider = ManualProvider()
        let cache = make(provider: provider)
        for _ in 0..<100 {
            #expect(cache.value(for: 1) == nil)   // returns immediately, nothing cached yet
        }
        #expect(provider.starts.count == 1)       // single-flight
    }

    @Test func completedResultIsReturnedOnTheNextCall() {
        let provider = ManualProvider()
        let cache = make(provider: provider)
        _ = cache.value(for: 1)
        provider.starts[0].complete("image")
        #expect(cache.value(for: 1) == "image")
    }

    @Test func previousValueIsKeptWhileRefreshing() {
        let time = ManualClock()
        let provider = ManualProvider()
        let cache = make(provider: provider, clock: { time.now })
        _ = cache.value(for: 1)
        provider.starts[0].complete("old")
        time.now = 5                                    // stale: refresh starts, old value still served
        #expect(cache.value(for: 1) == "old")
        #expect(provider.starts.count == 2)
        #expect(cache.value(for: 1) == "old")
        #expect(provider.starts.count == 2)        // still single-flight
    }

    @Test func lateResultAfterInvalidateIsDiscarded() {
        let provider = ManualProvider()
        let cache = make(provider: provider)
        _ = cache.value(for: 1)
        cache.invalidate()
        provider.starts[0].complete("late")
        #expect(cache.value(for: 1) == nil)
    }

    @Test func completionIsIdempotent() {
        let provider = ManualProvider()
        let cache = make(provider: provider)
        _ = cache.value(for: 1)
        provider.starts[0].complete("first")
        provider.starts[0].complete("second")      // e.g. a timeout and the real result both arrive
        #expect(cache.value(for: 1) == "first")
    }

    @Test func globalInFlightLimitIsRespected() {
        let provider = ManualProvider()
        let cache = make(provider: provider, maxInFlight: 2)
        for key in 0..<10 { _ = cache.value(for: key) }
        #expect(provider.starts.count == 2)
    }

    @Test func failedCaptureLeavesPreviousValueAndAllowsRetry() {
        let time = ManualClock()
        let provider = ManualProvider()
        let cache = make(provider: provider, clock: { time.now })
        _ = cache.value(for: 1)
        provider.starts[0].complete("ok")
        time.now = 5
        _ = cache.value(for: 1)
        provider.starts[1].complete(nil)           // capture failed
        #expect(cache.value(for: 1) == "ok")
        #expect(provider.starts.count == 2)        // cooling down: no retry storm
        time.now = 7
        #expect(cache.value(for: 1) == "ok")
        #expect(provider.starts.count == 3)        // retried after maxAge
    }

    @Test func expiredOperationsKeepTheirSlotUntilTheyReallyFinish() {
        let time = ManualClock()
        let provider = ManualProvider()
        let cache = make(provider: provider, maxInFlight: 2, clock: { time.now })
        _ = cache.value(for: 1)
        _ = cache.value(for: 2)
        #expect(provider.starts.count == 2)
        provider.starts[0].expire()          // timeout: result gone, work still running
        provider.starts[1].expire()
        time.now = 10                              // well past the cooldown
        for key in 1...6 { _ = cache.value(for: key) }
        #expect(provider.starts.count == 2)  // no third operation while orphans live
        provider.starts[0].finish()           // real end of the first one
        _ = cache.value(for: 3)
        #expect(provider.starts.count == 3)
    }

    @Test func sameKeyIsNotRestartedWhileItsOrphanLives() {
        let time = ManualClock()
        let provider = ManualProvider()
        let cache = make(provider: provider, maxInFlight: 4, clock: { time.now })
        _ = cache.value(for: 1)
        provider.starts[0].expire()
        time.now = 10
        _ = cache.value(for: 1)
        #expect(provider.starts.count == 1)
        provider.starts[0].finish()
        _ = cache.value(for: 1)
        #expect(provider.starts.count == 2)
    }

    @Test func lateResultFromAnExpiredOperationIsDiscarded() {
        let provider = ManualProvider()
        let cache = make(provider: provider)
        _ = cache.value(for: 1)
        provider.starts[0].expire()
        provider.starts[0].complete("late")   // real result arrives after the timeout
        #expect(cache.value(for: 1) == nil)
    }

    @Test func staleCooldownsAreCleaned() {
        let time = ManualClock()
        let provider = ManualProvider()
        let cache = BackgroundCaptureCache<Int, String>(
            maxInFlight: 100, maxAge: 1, maxEntries: 3, now: { time.now }, start: provider.start
        )
        for key in 0..<50 {
            _ = cache.value(for: key)
            provider.starts[provider.starts.count - 1].complete(nil)   // fail: cooldown recorded
            time.now += 0.1
        }
        #expect(cache.cooldownCount <= 11)       // only cooldowns younger than maxAge are kept
        time.now += 5
        _ = cache.value(for: 999)
        provider.starts[provider.starts.count - 1].complete(nil)
        #expect(cache.cooldownCount == 1)
    }
}
