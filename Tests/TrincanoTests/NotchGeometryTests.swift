//
//  NotchGeometryTests.swift
//  TrincanoTests
//
//  Fixtures: the Air M4 is measured on the Paulo's Mac; the MacBook Pro 14/16
//  values come from the upstream test data; the "pill" fixture is synthetic
//  (no device available): the geometry is read only from the safe area, so a
//  wider/taller pill is handled the same way as a rectangular notch.
//

import CoreGraphics
import Testing

struct NotchGeometryTests {
    private func airM4() -> NotchGeometry? {
        NotchGeometry(
            screenFrame: CGRect(x: 0, y: 0, width: 1470, height: 956),
            safeAreaTop: 32,
            auxiliaryTopLeftArea: CGRect(x: 0, y: 924, width: 646, height: 32),
            auxiliaryTopRightArea: CGRect(x: 825, y: 924, width: 645, height: 32)
        )
    }

    @Test func airM4NotchIs179By32Points() throws {
        let notch = try #require(airM4())
        #expect(notch.frame == CGRect(x: 646, y: 924, width: 179, height: 32))
        #expect(notch.rightSafeArea == CGRect(x: 825, y: 924, width: 645, height: 32))
    }

    @Test func macBookPro14UsesItsOwnWidth() throws {
        let notch = try #require(NotchGeometry(
            screenFrame: CGRect(x: 0, y: 0, width: 1512, height: 982),
            safeAreaTop: 32,
            auxiliaryTopLeftArea: CGRect(x: 0, y: 950, width: 664, height: 32),
            auxiliaryTopRightArea: CGRect(x: 848, y: 950, width: 664, height: 32)
        ))
        #expect(notch.frame.width == 184)
        #expect(notch.frame.minX == 664)
    }

    @Test func macBookPro16HasATallerNotch() throws {
        let notch = try #require(NotchGeometry(
            screenFrame: CGRect(x: 0, y: 0, width: 1728, height: 1117),
            safeAreaTop: 37,
            auxiliaryTopLeftArea: CGRect(x: 0, y: 1080, width: 772, height: 37),
            auxiliaryTopRightArea: CGRect(x: 956, y: 1080, width: 772, height: 37)
        ))
        #expect(notch.frame == CGRect(x: 772, y: 1080, width: 184, height: 37))
    }

    @Test func syntheticPillIsHandledByGeometryAlone() throws {
        // Wider and taller than any rectangular notch; nothing is hard-coded.
        let notch = try #require(NotchGeometry(
            screenFrame: CGRect(x: 0, y: 0, width: 1600, height: 1000),
            safeAreaTop: 40,
            auxiliaryTopLeftArea: CGRect(x: 0, y: 960, width: 690, height: 40),
            auxiliaryTopRightArea: CGRect(x: 910, y: 960, width: 690, height: 40)
        ))
        #expect(notch.frame.width == 220)
        #expect(notch.contains(CGPoint(x: 800, y: 990)))
    }

    @Test func displayNotAtTheOriginKeepsGlobalCoordinates() throws {
        // Laptop below an external monitor and shifted right: aux areas are global.
        let notch = try #require(NotchGeometry(
            screenFrame: CGRect(x: 100, y: -956, width: 1470, height: 956),
            safeAreaTop: 32,
            auxiliaryTopLeftArea: CGRect(x: 100, y: -32, width: 646, height: 32),
            auxiliaryTopRightArea: CGRect(x: 925, y: -32, width: 645, height: 32)
        ))
        #expect(notch.frame == CGRect(x: 746, y: -32, width: 179, height: 32))
        #expect(notch.contains(CGPoint(x: 800, y: -10)))
        #expect(notch.contains(CGPoint(x: 300, y: -10)) == false)
    }

    @Test func noNotchWithoutSafeAreaOrAuxiliaryAreas() {
        let frame = CGRect(x: 0, y: 0, width: 2560, height: 1440)
        #expect(NotchGeometry(screenFrame: frame, safeAreaTop: 0,
                              auxiliaryTopLeftArea: nil, auxiliaryTopRightArea: nil) == nil)
        #expect(NotchGeometry(screenFrame: frame, safeAreaTop: 32,
                              auxiliaryTopLeftArea: CGRect(x: 0, y: 0, width: 600, height: 32),
                              auxiliaryTopRightArea: nil) == nil)
    }

    @Test func degenerateAreasAreRejected() {
        // Right area starts before the left one ends: not a notch.
        let frame = CGRect(x: 0, y: 0, width: 1470, height: 956)
        #expect(NotchGeometry(screenFrame: frame, safeAreaTop: 32,
                              auxiliaryTopLeftArea: CGRect(x: 0, y: 924, width: 800, height: 32),
                              auxiliaryTopRightArea: CGRect(x: 700, y: 924, width: 770, height: 32)) == nil)
    }

    @Test func clickAreaIncludesTheScreenTopEdge() throws {
        let notch = try #require(airM4())
        // The pointer can sit exactly at the screen's top edge (y == maxY).
        #expect(notch.contains(CGPoint(x: 700, y: 956)))
        #expect(notch.contains(CGPoint(x: 700, y: 923)) == false)
        #expect(notch.contains(CGPoint(x: 645, y: 940)) == false)
        #expect(notch.contains(CGPoint(x: 826, y: 940)) == false)
    }
}
