//
//  RefreshSequencerTests.swift
//  TrincanoTests
//

import Testing

struct RefreshSequencerTests {
    @Test func onlyTheLatestTokenIsCurrent() {
        var s = RefreshSequencer()
        let a = s.begin()
        #expect(s.isCurrent(a))
        let b = s.begin()
        #expect(s.isCurrent(a) == false)
        #expect(s.isCurrent(b))
    }

    @Test func invalidateSupersedesEverythingInFlight() {
        var s = RefreshSequencer()
        let a = s.begin()
        s.invalidate()
        #expect(s.isCurrent(a) == false)
    }
}
