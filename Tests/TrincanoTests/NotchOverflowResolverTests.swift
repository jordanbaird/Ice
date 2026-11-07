//
//  NotchOverflowResolverTests.swift
//  TrincanoTests
//
//  Ported from lxy1992/Ice (scripts/test-notch-overflow.swift) to Swift Testing.
//

import CoreGraphics
import Testing

struct NotchOverflowResolverTests {
    private let visibleItemBounds: [CGRect?] = [
        CGRect(x: 573, y: 0, width: 38, height: 33),
        CGRect(x: 611, y: 0, width: 38, height: 33),
        CGRect(x: 649, y: 0, width: 38, height: 33),
        CGRect(x: 687, y: 0, width: 107, height: 33),
        CGRect(x: 794, y: 0, width: 124, height: 33),
        CGRect(x: 918, y: 0, width: 48, height: 33),
        CGRect(x: 1338, y: 0, width: 33, height: 33),
    ]

    @Test func selectsItemsPushedLeftOfThe14InchNotch() {
        let result = NotchOverflowResolver.obscuredIndices(
            itemBounds: visibleItemBounds,
            excluding: [6],
            screenBounds: CGRect(x: 0, y: 0, width: 1_512, height: 982),
            rightSafeArea: CGRect(x: 848, y: 950, width: 664, height: 32),
            menuBarHeight: 33
        )
        #expect(result == [0, 1, 2, 3, 4])
    }

    @Test func usesTheLargerNotchedDisplaysOwnSafeArea() {
        let result = NotchOverflowResolver.obscuredIndices(
            itemBounds: [
                CGRect(x: 870, y: 0, width: 40, height: 37),
                CGRect(x: 915, y: 0, width: 80, height: 37),
                CGRect(x: 956, y: 0, width: 40, height: 37),
                CGRect(x: 1_600, y: 0, width: 40, height: 37),
            ],
            excluding: [],
            screenBounds: CGRect(x: 0, y: 0, width: 1_728, height: 1_117),
            rightSafeArea: CGRect(x: 956, y: 1_080, width: 772, height: 37),
            menuBarHeight: 37
        )
        #expect(result == [0, 1])
    }

    @Test func addsNothingOnADisplayWithoutANotch() {
        let result = NotchOverflowResolver.obscuredIndices(
            itemBounds: visibleItemBounds,
            excluding: [],
            screenBounds: CGRect(x: 0, y: 0, width: 2_560, height: 1_440),
            rightSafeArea: nil,
            menuBarHeight: 0
        )
        #expect(result.isEmpty)
    }

    @Test func usesTheSelectedDisplaysCoordinateSpaceInAMultiDisplayLayout() {
        let result = NotchOverflowResolver.obscuredIndices(
            itemBounds: [
                CGRect(x: 700, y: 0, width: 38, height: 33),
                CGRect(x: 2_570, y: 0, width: 38, height: 33),
                CGRect(x: 2_768, y: 0, width: 38, height: 33),
            ],
            excluding: [],
            screenBounds: CGRect(x: 1_920, y: 0, width: 1_512, height: 982),
            rightSafeArea: CGRect(x: 2_768, y: 950, width: 664, height: 32),
            menuBarHeight: 33
        )
        #expect(result == [1])
    }

    @Test func ignoresMissingOffscreenAndRightSafeAreaItems() {
        let result = NotchOverflowResolver.obscuredIndices(
            itemBounds: [
                nil,
                CGRect(x: -5_000, y: 0, width: 38, height: 33),
                CGRect(x: 848, y: 0, width: 38, height: 33),
            ],
            excluding: [],
            screenBounds: CGRect(x: 0, y: 0, width: 1_512, height: 982),
            rightSafeArea: CGRect(x: 848, y: 950, width: 664, height: 32),
            menuBarHeight: 33
        )
        #expect(result.isEmpty)
    }

    @Test func stackedDisplaysAlignedInXOnlySelectTheNotebooksItems() {
        // External monitor above (CG y from 0), notebook below it (CG y from 1080).
        // Both share the same x range, so x alone cannot tell them apart.
        let externalBar = [
            CGRect(x: 700, y: 0, width: 38, height: 24),
            CGRect(x: 760, y: 0, width: 38, height: 24),
        ]
        let notebookBar = [
            CGRect(x: 700, y: 1_080, width: 38, height: 33),
            CGRect(x: 1_300, y: 1_080, width: 38, height: 33),
        ]
        let all: [CGRect?] = externalBar + notebookBar
        let result = NotchOverflowResolver.obscuredIndices(
            itemBounds: all,
            excluding: [],
            screenBounds: CGRect(x: 0, y: 1_080, width: 1_470, height: 956),
            rightSafeArea: CGRect(x: 825, y: 924, width: 645, height: 32),
            menuBarHeight: 33
        )
        #expect(result == [2])          // only the notebook's item left of the notch
    }

    @Test func itemsBelowTheMenuBarStripAreIgnored() {
        let result = NotchOverflowResolver.obscuredIndices(
            itemBounds: [CGRect(x: 700, y: 200, width: 38, height: 33)],
            excluding: [],
            screenBounds: CGRect(x: 0, y: 0, width: 1_470, height: 956),
            rightSafeArea: CGRect(x: 825, y: 924, width: 645, height: 32),
            menuBarHeight: 33
        )
        #expect(result.isEmpty)
    }
}
