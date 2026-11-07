//
//  NotchClickResolverTests.swift
//  TrincanoTests
//

import CoreGraphics
import Testing

struct NotchClickResolverTests {
    // Notebook below an external monitor, shifted right (AppKit global, y up).
    private let external = CGRect(x: -225, y: 956, width: 1920, height: 1080)
    private let laptop = CGRect(x: 0, y: 0, width: 1470, height: 956)

    private func screens() -> [NotchClickResolver.Screen] {
        [
            NotchClickResolver.Screen(frame: external, notch: nil),
            NotchClickResolver.Screen(
                frame: laptop,
                notch: NotchGeometry(
                    screenFrame: laptop,
                    safeAreaTop: 32,
                    auxiliaryTopLeftArea: CGRect(x: 0, y: 924, width: 646, height: 32),
                    auxiliaryTopRightArea: CGRect(x: 825, y: 924, width: 645, height: 32)
                )
            ),
        ]
    }

    private func resolve(_ point: CGPoint, enabled: Bool = true, leftButton: Bool = true) -> NotchClickResolver.Decision {
        NotchClickResolver.resolve(point: point, screens: screens(), isEnabled: enabled, isLeftButton: leftButton)
    }

    @Test func clickInTheNotebookNotchOpensTheBarEvenWithKeyboardFocusOnTheExternal() {
        // The decision depends only on the click point, never on `NSScreen.main`.
        #expect(resolve(CGPoint(x: 700, y: 940)) == .toggleBar(screenIndex: 1))
    }

    @Test func clickOnTheScreenTopEdgeStillCountsAsTheNotebook() {
        // Strictly inside the notebook, on its top pixel row.
        #expect(resolve(CGPoint(x: 700, y: 955.5)) == .toggleBar(screenIndex: 1))
    }

    @Test func clickJustOutsideTheNotchDoesNothing() {
        #expect(resolve(CGPoint(x: 645, y: 940)) == .none)
        #expect(resolve(CGPoint(x: 826, y: 940)) == .none)
        #expect(resolve(CGPoint(x: 700, y: 923)) == .none)
    }

    @Test func rightClickDoesNothing() {
        #expect(resolve(CGPoint(x: 700, y: 940), leftButton: false) == .none)
    }

    @Test func disabledSettingDoesNothing() {
        #expect(resolve(CGPoint(x: 700, y: 940), enabled: false) == .none)
    }

    @Test func clickOnTheExternalMonitorNeverTogglesTheBar() {
        #expect(resolve(CGPoint(x: 700, y: 2000)) == .none)
        #expect(resolve(CGPoint(x: 700, y: 1000)) == .none)
    }

    @Test func pointOutsideEveryScreenDoesNothing() {
        #expect(resolve(CGPoint(x: 9000, y: 9000)) == .none)
    }
}
