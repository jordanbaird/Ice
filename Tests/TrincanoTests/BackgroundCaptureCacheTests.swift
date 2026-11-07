//
//  BackgroundCaptureCacheTests.swift
//  TrincanoTests
//

import Foundation
import Testing

struct BackgroundCaptureCacheTests {
    /// A provider the test completes by hand, simulating a stuck or slow capture.
    private final class ManualProvider {
        var starts = [(key: Int, complete: (String?) -> Void)]()
        func start(_ key: Int, _ complete: @escaping (String?) -> Void) {
            starts.append((key, complete))
        }
    }

    private func make(
        provider: ManualProvider,
        maxInFlight: Int = 1,
        clock: @escaping () -> TimeInterval = { 0 }
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
        var now: TimeInterval = 0
        let provider = ManualProvider()
        let cache = make(provider: provider, clock: { now })
        _ = cache.value(for: 1)
        provider.starts[0].complete("old")
        now = 5                                    // stale: refresh starts, old value still served
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
        var now: TimeInterval = 0
        let provider = ManualProvider()
        let cache = make(provider: provider, clock: { now })
        _ = cache.value(for: 1)
        provider.starts[0].complete("ok")
        now = 5
        _ = cache.value(for: 1)
        provider.starts[1].complete(nil)           // capture failed
        #expect(cache.value(for: 1) == "ok")
        #expect(provider.starts.count == 2)        // cooling down: no retry storm
        now = 7
        #expect(cache.value(for: 1) == "ok")
        #expect(provider.starts.count == 3)        // retried after maxAge
    }
}
