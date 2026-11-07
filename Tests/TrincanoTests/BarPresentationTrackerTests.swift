//
//  BarPresentationTrackerTests.swift
//  TrincanoTests
//

import Testing

struct BarPresentationTrackerTests {
    private enum Section { case hidden, alwaysHidden }

    @Test func displayStillConnectedKeepsThePresentation() {
        var tracker = BarPresentationTracker<Section>()
        let token = tracker.begin(displayID: 2, section: .hidden)
        #expect(tracker.reconcile(connectedDisplayIDs: [1, 2]) == nil)
        #expect(tracker.canPublish(token: token, connectedDisplayIDs: [1, 2]))
    }

    @Test func visibleBarWhoseDisplayWasRemovedIsClosedEvenIfTheWindowsScreenIsGone() {
        // The decision depends only on the identity captured when the show began.
        var tracker = BarPresentationTracker<Section>()
        _ = tracker.begin(displayID: 2, section: .hidden)
        #expect(tracker.reconcile(connectedDisplayIDs: [1]) == .hidden)
        #expect(tracker.presentation == nil)
    }

    @Test func remappedDisplayIDsStillCloseTheBarOfTheRemovedOne() {
        // The window moved to the notebook (its screen now reads as display 1),
        // but the bar was presented on display 2, which is gone.
        var tracker = BarPresentationTracker<Section>()
        _ = tracker.begin(displayID: 2, section: .hidden)
        #expect(tracker.reconcile(connectedDisplayIDs: [1, 3]) == .hidden)
    }

    @Test func removalDuringASlowRefreshCancelsThePublish() {
        var tracker = BarPresentationTracker<Section>()
        let token = tracker.begin(displayID: 2, section: .hidden)    // awaiting the cache
        _ = tracker.reconcile(connectedDisplayIDs: [1])              // display removed meanwhile
        #expect(tracker.canPublish(token: token, connectedDisplayIDs: [1]) == false)
    }

    @Test func theSectionActuallyPresentedIsTheOneClosed() {
        var tracker = BarPresentationTracker<Section>()
        _ = tracker.begin(displayID: 2, section: .alwaysHidden)
        #expect(tracker.reconcile(connectedDisplayIDs: [1]) == .alwaysHidden)
    }

    @Test func doesNotReappearWhenTheDisplayComesBack() {
        var tracker = BarPresentationTracker<Section>()
        let old = tracker.begin(displayID: 2, section: .hidden)
        _ = tracker.reconcile(connectedDisplayIDs: [1])
        #expect(tracker.canPublish(token: old, connectedDisplayIDs: [1, 2]) == false)
        let fresh = tracker.begin(displayID: 2, section: .hidden)   // a new, explicit show
        #expect(tracker.canPublish(token: fresh, connectedDisplayIDs: [1, 2]))
    }

    @Test func staleTokenAfterANewerShowCannotPublish() {
        var tracker = BarPresentationTracker<Section>()
        let first = tracker.begin(displayID: 1, section: .hidden)
        let second = tracker.begin(displayID: 1, section: .alwaysHidden)
        #expect(tracker.canPublish(token: first, connectedDisplayIDs: [1]) == false)
        #expect(tracker.canPublish(token: second, connectedDisplayIDs: [1]))
    }

    @Test func publishNeedsTheTargetDisplayToBeConnected() {
        var tracker = BarPresentationTracker<Section>()
        let token = tracker.begin(displayID: 2, section: .hidden)
        #expect(tracker.canPublish(token: token, connectedDisplayIDs: [1]) == false)
    }

    @Test func endedPresentationHasNothingToReconcile() {
        var tracker = BarPresentationTracker<Section>()
        _ = tracker.begin(displayID: 2, section: .hidden)
        tracker.end()
        #expect(tracker.reconcile(connectedDisplayIDs: [1]) == nil)
    }
}
