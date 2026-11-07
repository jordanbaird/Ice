//
//  SectionSessionTests.swift
//  TrincanoTests
//

import Testing

struct SectionSessionTests {
    /// Counts the real effects `MenuBarSection` triggers (monitor/timer arm and
    /// disarm, hiding the section).
    private final class Recorder {
        var arms = 0
        var disarms = 0
        var hides = 0
        lazy var session = SectionSession(effects: .init(
            armRehide: { self.arms += 1 },
            disarmRehide: { self.disarms += 1 },
            hideSection: { self.hides += 1 }
        ))
        /// Net number of live monitors/timers.
        var liveRehideChecks: Int { session.isRehideArmed ? 1 : 0 }
    }

    @Test func suspendedBarShowThenDisplayRemovedNeverArmsTheRehide() {
        let r = Recorder()
        let token = r.session.begin { 2 }                    // show on the external; awaiting the cache
        r.session.reconcile(connectedDisplayIDs: [1])        // display removed meanwhile
        #expect(r.hides == 1)
        let armed = r.session.armRehideIfCurrent(token)      // the awaited show returns without publishing
        #expect(armed == false)
        #expect(r.arms == 0)
        #expect(r.liveRehideChecks == 0)
    }

    @Test func suspendedShowThenHideNeverArmsTheRehide() {
        let r = Recorder()
        let token = r.session.begin { 1 }
        r.session.end()                                      // section.hide()
        #expect(r.session.armRehideIfCurrent(token) == false)
        #expect(r.arms == 0)
        #expect(r.liveRehideChecks == 0)
    }

    @Test func suspendedShowInBarOnTheAlwaysHiddenSectionBehavesTheSame() {
        // showInBar and the always-hidden section use the same session API.
        let r = Recorder()
        let token = r.session.begin { 2 }
        r.session.reconcile(connectedDisplayIDs: [1, 3])
        #expect(r.session.armRehideIfCurrent(token) == false)
        #expect(r.arms == 0 && r.liveRehideChecks == 0)
    }

    @Test func aNewShowInvalidatesTheTokenOfASuspendedOne() {
        let r = Recorder()
        let first = r.session.begin { 1 }
        let second = r.session.begin { 1 }
        #expect(r.session.armRehideIfCurrent(first) == false)
        #expect(r.session.armRehideIfCurrent(second))
        #expect(r.arms == 1)
    }

    @Test func aCompletedShowOnAConnectedDisplayArmsTheRehideOnce() {
        let r = Recorder()
        let token = r.session.begin { 2 }
        #expect(r.session.armRehideIfCurrent(token))
        r.session.reconcile(connectedDisplayIDs: [1, 2])     // nothing changed for it
        #expect(r.arms == 1 && r.hides == 0)
        #expect(r.liveRehideChecks == 1)
    }

    @Test func inlineSectionOnARemovedDisplayWithNoTimerArmedIsHidden() {
        let r = Recorder()
        _ = r.session.begin { 2 }                            // inline on the external; cursor in the bar: no timer armed
        #expect(r.arms == 0)
        r.session.reconcile(connectedDisplayIDs: [1])        // external disconnected
        #expect(r.hides == 1)                                // section hidden
        #expect(r.session.isActive == false)                 // session ended
        #expect(r.session.pinnedDisplayID == nil)
        #expect(r.disarms >= 1)                              // monitor/timer stopped
        #expect(r.liveRehideChecks == 0)
    }

    @Test func inlineSectionWithATimerArmedIsAlsoTornDown() {
        let r = Recorder()
        let token = r.session.begin { 2 }
        _ = r.session.armRehideIfCurrent(token)
        r.session.reconcile(connectedDisplayIDs: [1])
        #expect(r.hides == 1)
        #expect(r.liveRehideChecks == 0)
    }

    @Test func inactiveSessionIgnoresDisplayChanges() {
        let r = Recorder()
        r.session.reconcile(connectedDisplayIDs: [1])
        #expect(r.hides == 0)
    }

    @Test func theRehideTimerCannotRearmAnEndedSession() {
        let r = Recorder()
        _ = r.session.begin { 1 }
        r.session.end()
        r.session.rearmIfActive()
        #expect(r.arms == 0)
    }

    @Test func rearmKeepsAnActiveSessionArmed() {
        let r = Recorder()
        _ = r.session.begin { 1 }
        r.session.rearmIfActive()
        #expect(r.arms == 1)
    }
}
