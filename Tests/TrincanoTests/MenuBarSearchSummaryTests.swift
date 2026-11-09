//
//  MenuBarSearchSummaryTests.swift
//  TrincanoTests
//

import Testing

struct MenuBarSearchSummaryTests {
    @Test func emptyQueryShowsTheTotal() {
        #expect(MenuBarSearchSummary(query: "", shown: 14, total: 14) == .total(14))
    }

    @Test func whitespaceOnlyQueryCountsAsNoQuery() {
        #expect(MenuBarSearchSummary(query: "  \n ", shown: 3, total: 14) == .total(14))
    }

    @Test func queryWithMatchesShowsShownOfTotal() {
        #expect(MenuBarSearchSummary(query: "back", shown: 3, total: 38) == .filtered(shown: 3, total: 38))
    }

    @Test func queryWithoutMatchesIsNoResultsAndKeepsTheTrimmedQuery() {
        let summary = MenuBarSearchSummary(query: "  figma ", shown: 0, total: 14)
        #expect(summary == .noResults(query: "figma"))
        #expect(summary.isNoResults)
    }

    @Test func totalNeverSmallerThanShown() {
        // The cache can shrink between the filter and the count.
        #expect(MenuBarSearchSummary(query: "a", shown: 5, total: 3) == .filtered(shown: 5, total: 5))
    }

    @Test func totalIsNotNoResultsEvenWithZeroItems() {
        #expect(!MenuBarSearchSummary(query: "", shown: 0, total: 0).isNoResults)
    }
}
