//
//  NotchBarPolicyTests.swift
//  TrincanoTests
//

import Testing

struct NotchBarPolicyTests {
    // Air M4: the right safe area is 645 pt wide.
    private let airRight: Double = 645

    @Test func doesNothingWhenTheSettingIsOff() {
        let use = NotchBarPolicy.shouldUseBar(
            isEnabled: false, rightSafeAreaWidth: airRight, obscuredCount: 3, expandedItemWidths: [300, 300, 300]
        )
        #expect(use == false)
    }

    @Test func doesNothingOnAScreenWithoutANotch() {
        let use = NotchBarPolicy.shouldUseBar(
            isEnabled: true, rightSafeAreaWidth: nil, obscuredCount: 3, expandedItemWidths: [3000]
        )
        #expect(use == false)
    }

    @Test func usesTheBarWhenItemsAreAlreadyBehindTheNotch() {
        let use = NotchBarPolicy.shouldUseBar(
            isEnabled: true, rightSafeAreaWidth: airRight, obscuredCount: 1, expandedItemWidths: [100]
        )
        #expect(use)
    }

    @Test func usesTheBarWhenTheExpandedItemsWontFitBesideTheNotch() {
        let widths = Array(repeating: 40.0, count: 20)      // 800 pt > 645 pt
        let use = NotchBarPolicy.shouldUseBar(
            isEnabled: true, rightSafeAreaWidth: airRight, obscuredCount: 0, expandedItemWidths: widths
        )
        #expect(use)
    }

    @Test func staysInlineWhenEverythingFits() {
        let widths = Array(repeating: 40.0, count: 10)      // 400 pt
        let use = NotchBarPolicy.shouldUseBar(
            isEnabled: true, rightSafeAreaWidth: airRight, obscuredCount: 0, expandedItemWidths: widths
        )
        #expect(use == false)
    }

    @Test func keepsASafetyMarginAtTheNotchEdge() {
        // Exactly the available width leaves no margin: treat as not fitting.
        let exact = NotchBarPolicy.shouldUseBar(
            isEnabled: true, rightSafeAreaWidth: airRight, obscuredCount: 0, expandedItemWidths: [airRight]
        )
        #expect(exact)
        let justFits = NotchBarPolicy.shouldUseBar(
            isEnabled: true, rightSafeAreaWidth: airRight, obscuredCount: 0,
            expandedItemWidths: [airRight - NotchBarPolicy.margin]
        )
        #expect(justFits == false)
    }

    @Test func widerSafeAreaOfALargerScreenFitsMore() {
        let widths = Array(repeating: 40.0, count: 20)      // 800 pt
        let use = NotchBarPolicy.shouldUseBar(
            isEnabled: true, rightSafeAreaWidth: 772, obscuredCount: 0, expandedItemWidths: widths
        )
        #expect(use)    // 800 > 772 - margin
        let wide = NotchBarPolicy.shouldUseBar(
            isEnabled: true, rightSafeAreaWidth: 1000, obscuredCount: 0, expandedItemWidths: widths
        )
        #expect(wide == false)
    }
}

struct NotchClickPolicyTests {
    @Test func opensOnlyWhenEnabledAndClickedInsideTheNotch() {
        #expect(NotchClickPolicy.shouldToggleBar(isEnabled: true, hasNotch: true, clickIsInsideNotch: true))
        #expect(NotchClickPolicy.shouldToggleBar(isEnabled: false, hasNotch: true, clickIsInsideNotch: true) == false)
        #expect(NotchClickPolicy.shouldToggleBar(isEnabled: true, hasNotch: false, clickIsInsideNotch: true) == false)
        #expect(NotchClickPolicy.shouldToggleBar(isEnabled: true, hasNotch: true, clickIsInsideNotch: false) == false)
    }
}
