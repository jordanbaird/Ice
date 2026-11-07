//
//  TimedMemoTests.swift
//  TrincanoTests
//

import Testing

struct TimedMemoTests {
    @Test func computesOnceWithinTheTTL() {
        var memo = TimedMemo<Int>(ttl: 0.25)
        var calls = 0
        func compute() -> Int { calls += 1; return calls }
        #expect(memo.value(now: 0, compute: compute) == 1)
        #expect(memo.value(now: 0.1, compute: compute) == 1)
        #expect(memo.value(now: 0.249, compute: compute) == 1)
        #expect(calls == 1)
    }

    @Test func recomputesAfterTheTTL() {
        var memo = TimedMemo<Int>(ttl: 0.25)
        var calls = 0
        func compute() -> Int { calls += 1; return calls }
        _ = memo.value(now: 0, compute: compute)
        #expect(memo.value(now: 0.25, compute: compute) == 2)
        #expect(calls == 2)
    }

    @Test func invalidateForcesARecompute() {
        var memo = TimedMemo<Int>(ttl: 10)
        var calls = 0
        func compute() -> Int { calls += 1; return calls }
        _ = memo.value(now: 0, compute: compute)
        memo.invalidate()
        #expect(memo.value(now: 1, compute: compute) == 2)
    }

    @Test func nilResultsAreCachedToo() {
        var memo = TimedMemo<Int?>(ttl: 1)
        var calls = 0
        func compute() -> Int? { calls += 1; return nil }
        _ = memo.value(now: 0, compute: compute)
        _ = memo.value(now: 0.5, compute: compute)
        #expect(calls == 1)
    }

    @Test func clockGoingBackwardsRecomputes() {
        var memo = TimedMemo<Int>(ttl: 1)
        var calls = 0
        func compute() -> Int { calls += 1; return calls }
        _ = memo.value(now: 100, compute: compute)
        _ = memo.value(now: 5, compute: compute)
        #expect(calls == 2)
    }
}
