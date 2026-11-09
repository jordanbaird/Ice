//
//  SectionCountSummaryTests.swift
//  TrincanoTests
//

import Testing

struct SectionCountSummaryTests {
    @Test func emptySectionIsFlaggedEmpty() {
        let summary = SectionCountSummary(itemCount: 0)
        #expect(summary.isEmpty)
        #expect(!summary.showsNotchNote)
    }

    @Test func sectionWithItemsIsNotEmpty() {
        #expect(!SectionCountSummary(itemCount: 3).isEmpty)
    }

    @Test func notchNoteAppearsOnlyWhenItemsAreBehindTheNotch() {
        #expect(!SectionCountSummary(itemCount: 6, behindNotchCount: 0).showsNotchNote)
        #expect(SectionCountSummary(itemCount: 6, behindNotchCount: 2).showsNotchNote)
    }

    @Test func behindNotchCountIsClampedToTheItemCount() {
        #expect(SectionCountSummary(itemCount: 2, behindNotchCount: 9).behindNotchCount == 2)
        #expect(SectionCountSummary(itemCount: 2, behindNotchCount: -1).behindNotchCount == 0)
        #expect(SectionCountSummary(itemCount: -4).itemCount == 0)
    }
}
