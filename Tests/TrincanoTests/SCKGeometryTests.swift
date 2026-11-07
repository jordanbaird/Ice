//
//  SCKGeometryTests.swift
//  TrincanoTests
//

import CoreGraphics
import Testing

struct SCKGeometryTests {
    // Global (Quartz, y-down) display frames.
    private let builtIn = CGRect(x: 0, y: 0, width: 1470, height: 956)
    private let right = CGRect(x: 1470, y: 0, width: 1920, height: 1080)
    private let above = CGRect(x: -225, y: -1080, width: 1920, height: 1080)   // monitor on top of the laptop
    private let leftBelow = CGRect(x: -1920, y: 300, width: 1920, height: 1080)

    @Test func mainDisplayKeepsOrigin() throws {
        let rect = CGRect(x: 100, y: 0, width: 200, height: 32)
        let r = try #require(SCKGeometry.sourceRect(forGlobalRect: rect, onDisplay: builtIn, scale: 2))
        #expect(r.rect == rect)
        #expect(r.pixelSize == CGSize(width: 400, height: 64))
    }

    @Test func displayToTheRightIsTranslated() throws {
        let rect = CGRect(x: 1570, y: 0, width: 200, height: 24)
        let r = try #require(SCKGeometry.sourceRect(forGlobalRect: rect, onDisplay: right, scale: 1))
        #expect(r.rect == CGRect(x: 100, y: 0, width: 200, height: 24))
        #expect(r.pixelSize == CGSize(width: 200, height: 24))
    }

    @Test func displayAboveWithNegativeOriginIsTranslated() throws {
        // Menu bar of a monitor on top of the notebook: y is negative in global space.
        let rect = CGRect(x: 0, y: -1080, width: 300, height: 24)
        let r = try #require(SCKGeometry.sourceRect(forGlobalRect: rect, onDisplay: above, scale: 2))
        #expect(r.rect == CGRect(x: 225, y: 0, width: 300, height: 24))
        #expect(r.pixelSize == CGSize(width: 600, height: 48))
    }

    @Test func displayToTheLeftAndBelowIsTranslated() throws {
        let rect = CGRect(x: -1000, y: 310, width: 100, height: 20)
        let r = try #require(SCKGeometry.sourceRect(forGlobalRect: rect, onDisplay: leftBelow, scale: 2))
        #expect(r.rect == CGRect(x: 920, y: 10, width: 100, height: 20))
    }

    @Test func rectSpanningTwoDisplaysIsClippedToTheDisplay() throws {
        let rect = CGRect(x: 1400, y: 0, width: 200, height: 24)
        let r = try #require(SCKGeometry.sourceRect(forGlobalRect: rect, onDisplay: builtIn, scale: 1))
        #expect(r.rect == CGRect(x: 1400, y: 0, width: 70, height: 24))
    }

    @Test func rectOutsideTheDisplayIsRejected() {
        let rect = CGRect(x: 5000, y: 5000, width: 10, height: 10)
        #expect(SCKGeometry.sourceRect(forGlobalRect: rect, onDisplay: builtIn, scale: 2) == nil)
    }

    @Test func subPointRectIsRejected() {
        let rect = CGRect(x: 10, y: 10, width: 0.5, height: 20)
        #expect(SCKGeometry.sourceRect(forGlobalRect: rect, onDisplay: builtIn, scale: 2) == nil)
    }
}
