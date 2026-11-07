//
//  NotchBarSessionTests.swift
//  TrincanoTests
//

import Testing

struct NotchBarSessionTests {
    private final class Items {
        var widths: [Double] = [40, 40, 40]      // same window IDs all the time
        var obscured = 0
        var reads = 0
    }

    private func begin(_ session: inout NotchBarSession, _ items: Items) -> Bool {
        session.begin(isEnabled: true, rightSafeAreaWidth: 645, obscuredCount: { items.obscured }, expandedItemWidths: {
            items.reads += 1
            return items.widths
        })
    }

    @Test func widthChangeWithConstantIDsIsSeenAtTheNextShow() {
        var session = NotchBarSession()
        let items = Items()
        #expect(begin(&session, items) == false)           // 120 pt: fits, inline
        session.end()
        items.widths = Array(repeating: 40, count: 20)     // a dynamic item grew; IDs unchanged
        #expect(begin(&session, items))                    // 800 pt: now the bar
        session.end()
    }

    @Test func inlineToBarToInlineTransition() {
        var session = NotchBarSession()
        let items = Items()
        #expect(begin(&session, items) == false)
        session.end()
        items.widths = Array(repeating: 40, count: 20)
        #expect(begin(&session, items))
        session.end()
        items.widths = [40, 40]                            // shrank again
        #expect(begin(&session, items) == false)           // no stale "use the bar"
        session.end()
    }

    @Test func decisionIsPinnedUntilTheSectionIsHidden() {
        var session = NotchBarSession()
        let items = Items()
        #expect(begin(&session, items) == false)
        let reads = items.reads
        items.widths = Array(repeating: 40, count: 20)     // grows while expanded inline
        #expect(session.isUsingBar == false)               // no flip mid-cycle
        #expect(items.reads == reads)                      // and no extra measurement
        session.end()
        #expect(session.isUsingBar == false)
    }

    @Test func alreadyObscuredItemsForceTheBarAndClearAfterEnd() {
        var session = NotchBarSession()
        let items = Items()
        items.obscured = 2
        #expect(begin(&session, items))
        #expect(session.isUsingBar)
        session.end()
        #expect(session.isUsingBar == false)
    }

    @Test func screenWithoutANotchNeverUsesTheBar() {
        var session = NotchBarSession()
        let used = session.begin(isEnabled: true, rightSafeAreaWidth: nil, obscuredCount: { 5 }, expandedItemWidths: { [9999] })
        #expect(used == false)
    }
}
