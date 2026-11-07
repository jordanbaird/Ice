//
//  PendingPIDTrackerTests.swift
//  TrincanoTests
//

import Testing

struct PendingPIDTrackerTests {
    private func tracker() -> PendingPIDTracker<UInt32> {
        PendingPIDTracker<UInt32>(delays: [30, 60, 120])
    }

    @Test func nothingDueWithoutFailures() {
        #expect(tracker().isRetryDue(among: [1, 2], now: 100) == false)
    }

    @Test func failureIsNotDueBeforeTTLAndIsDueAfter() {
        var t = tracker()
        t.recordFailure(1, now: 0)
        #expect(t.isRetryDue(among: [1], now: 0) == false)
        #expect(t.isRetryDue(among: [1], now: 29) == false)
        #expect(t.isRetryDue(among: [1], now: 31))
    }

    @Test func stableIDsStillBecomeDue() {
        var t = tracker()
        t.recordFailure(1, now: 0)
        // Same window IDs on every poll: only the clock makes it due.
        for now in stride(from: 1.0, to: 30.0, by: 5.0) {
            #expect(t.isRetryDue(among: [1, 2, 3], now: now) == false)
        }
        #expect(t.isRetryDue(among: [1, 2, 3], now: 30.5))
    }

    @Test func backoffGrowsAndIsCapped() {
        var t = tracker()
        t.recordFailure(1, now: 0)      // next due at 30
        t.recordFailure(1, now: 31)     // next due at 31 + 60
        #expect(t.isRetryDue(among: [1], now: 90) == false)
        #expect(t.isRetryDue(among: [1], now: 92))
        t.recordFailure(1, now: 92)     // + 120
        t.recordFailure(1, now: 300)    // capped at 120
        #expect(t.isRetryDue(among: [1], now: 419) == false)
        #expect(t.isRetryDue(among: [1], now: 421))
    }

    @Test func earlyFailureDoesNotEscalateTheBackoff() {
        var t = tracker()
        t.recordFailure(1, now: 0)      // due at 30
        t.recordFailure(1, now: 5)      // unrelated re-cache: ignored
        t.recordFailure(1, now: 10)
        #expect(t.isRetryDue(among: [1], now: 31))
    }

    @Test func failureThenSuccessClears() {
        var t = tracker()
        t.recordFailure(1, now: 0)
        t.recordSuccess(1)
        #expect(t.isRetryDue(among: [1], now: 1000) == false)
    }

    @Test func appsChangedMakesPendingDueNow() {
        var t = tracker()
        t.recordFailure(1, now: 0)
        t.appsChanged()
        #expect(t.isRetryDue(among: [1], now: 1))
    }

    @Test func appsChangedRestartsTheBackoffFromTheFirstDelay() {
        var t = tracker()
        t.recordFailure(1, now: 0)
        t.recordFailure(1, now: 31)      // second failure: next delay is 60
        t.appsChanged()
        t.recordFailure(1, now: 100)     // policy: after an apps change the backoff restarts at 30 s
        #expect(t.isRetryDue(among: [1], now: 129) == false)
        #expect(t.isRetryDue(among: [1], now: 131))
    }

    @Test func pendingNotYetDueNeverTriggersARescan() {
        var t = tracker()
        t.recordFailure(1, now: 0)
        t.recordFailure(2, now: 10)
        // Polling every second: a rescan (which rebuilds all items) may only be
        // requested once a pending window is due.
        for now in 0..<30 {
            #expect(t.isRetryDue(among: [1, 2, 3], now: Double(now)) == false)
        }
        #expect(t.isRetryDue(among: [1, 2, 3], now: 30))
    }

    @Test func onlyPendingIDsStillOnScreenCount() {
        var t = tracker()
        t.recordFailure(1, now: 0)
        #expect(t.isRetryDue(among: [2, 3], now: 100) == false)   // window 1 is gone
        t.prune(keeping: [2, 3])
        #expect(t.isRetryDue(among: [1], now: 100) == false)
    }
}
