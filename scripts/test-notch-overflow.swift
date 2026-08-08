import CoreGraphics
import Foundation

@main
private enum NotchOverflowResolverTests {
    static func main() {
        let visibleItemBounds: [CGRect?] = [
            CGRect(x: 573, y: 0, width: 38, height: 33),
            CGRect(x: 611, y: 0, width: 38, height: 33),
            CGRect(x: 649, y: 0, width: 38, height: 33),
            CGRect(x: 687, y: 0, width: 107, height: 33),
            CGRect(x: 794, y: 0, width: 124, height: 33),
            CGRect(x: 918, y: 0, width: 48, height: 33),
            CGRect(x: 1338, y: 0, width: 33, height: 33),
        ]

        assertEqual(
            NotchOverflowResolver.obscuredIndices(
                itemBounds: visibleItemBounds,
                excluding: [6],
                screenBounds: CGRect(x: 0, y: 0, width: 1_512, height: 982),
                rightSafeArea: CGRect(x: 848, y: 950, width: 664, height: 32)
            ),
            [0, 1, 2, 3, 4],
            "selects visible items pushed left of the 14-inch MacBook Pro notch"
        )

        assertEqual(
            NotchOverflowResolver.obscuredIndices(
                itemBounds: [
                    CGRect(x: 870, y: 0, width: 40, height: 37),
                    CGRect(x: 915, y: 0, width: 80, height: 37),
                    CGRect(x: 956, y: 0, width: 40, height: 37),
                    CGRect(x: 1_600, y: 0, width: 40, height: 37),
                ],
                excluding: [],
                screenBounds: CGRect(x: 0, y: 0, width: 1_728, height: 1_117),
                rightSafeArea: CGRect(x: 956, y: 1_080, width: 772, height: 37)
            ),
            [0, 1],
            "uses the larger notched display's own safe area"
        )

        assertEqual(
            NotchOverflowResolver.obscuredIndices(
                itemBounds: visibleItemBounds,
                excluding: [],
                screenBounds: CGRect(x: 0, y: 0, width: 2_560, height: 1_440),
                rightSafeArea: nil
            ),
            [],
            "does not add overflow items on an external display without a notch"
        )

        assertEqual(
            NotchOverflowResolver.obscuredIndices(
                itemBounds: [
                    CGRect(x: 700, y: 0, width: 38, height: 33),
                    CGRect(x: 2_570, y: 0, width: 38, height: 33),
                    CGRect(x: 2_768, y: 0, width: 38, height: 33),
                ],
                excluding: [],
                screenBounds: CGRect(x: 1_920, y: 0, width: 1_512, height: 982),
                rightSafeArea: CGRect(x: 2_768, y: 950, width: 664, height: 32)
            ),
            [1],
            "uses the selected display's coordinate space in a multi-display layout"
        )

        assertEqual(
            NotchOverflowResolver.obscuredIndices(
                itemBounds: [
                    nil,
                    CGRect(x: -5_000, y: 0, width: 38, height: 33),
                    CGRect(x: 848, y: 0, width: 38, height: 33),
                ],
                excluding: [],
                screenBounds: CGRect(x: 0, y: 0, width: 1_512, height: 982),
                rightSafeArea: CGRect(x: 848, y: 950, width: 664, height: 32)
            ),
            [],
            "ignores missing, off-screen, and right-safe-area items"
        )

        print("PASS: notch overflow resolver")
    }

    private static func assertEqual<T: Equatable>(
        _ actual: T,
        _ expected: T,
        _ description: String
    ) {
        guard actual == expected else {
            fputs("FAIL: \(description) — expected \(expected), got \(actual)\n", stderr)
            exit(1)
        }
    }
}
