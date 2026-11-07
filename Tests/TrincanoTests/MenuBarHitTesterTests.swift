//
//  MenuBarHitTesterTests.swift
//  TrincanoTests
//

import CoreGraphics
import Testing

struct MenuBarHitTesterTests {
    /// Geometry the test can change at any time without any notification.
    private final class World {
        var menuFrame: CGRect? = CGRect(x: 100, y: 0, width: 200, height: 24)
        var items: [CGRect] = [CGRect(x: 1000, y: 0, width: 30, height: 24)]
        var menuCalls = 0
        var itemCalls = 0
    }

    private func make(_ world: World) -> MenuBarHitTester {
        MenuBarHitTester(
            applicationMenuFrame: { _ in world.menuCalls += 1; return world.menuFrame },
            itemBounds: { world.itemCalls += 1; return world.items }
        )
    }

    private let screenMinX: CGFloat = 0
    private let emptyPoint = CGPoint(x: 600, y: 10)
    private let newlyAddedMenuPoint = CGPoint(x: 400, y: 10)

    @Test func hoverReusesTheCachedGeometryWithinTheTTL() {
        let world = World()
        let tester = make(world)
        for i in 0..<50 {
            _ = tester.isEmptySpace(at: emptyPoint, displayKey: 1, screenMinX: screenMinX,
                                    now: Double(i) * 0.001, freshness: .cached)
        }
        #expect(world.menuCalls == 1)   // economy kept for movement
        #expect(world.itemCalls == 1)
    }

    @Test func clickAfterTheAppMenuGrewIsNotTreatedAsEmptySpace() {
        let world = World()
        let tester = make(world)
        // Warm the memo by hovering.
        #expect(tester.isEmptySpace(at: newlyAddedMenuPoint, displayKey: 1, screenMinX: screenMinX,
                                    now: 0, freshness: .cached))
        // The app menu grows (document/focus/modal) with no notification.
        world.menuFrame = CGRect(x: 100, y: 0, width: 400, height: 24)
        // A click inside the TTL must read fresh geometry.
        #expect(tester.isEmptySpace(at: newlyAddedMenuPoint, displayKey: 1, screenMinX: screenMinX,
                                    now: 0.1, freshness: .fresh) == false)
    }

    @Test func clickAfterAnItemAppearedIsNotTreatedAsEmptySpace() {
        let world = World()
        let tester = make(world)
        #expect(tester.isEmptySpace(at: emptyPoint, displayKey: 1, screenMinX: screenMinX,
                                    now: 0, freshness: .cached))
        world.items.append(CGRect(x: 580, y: 0, width: 40, height: 24))
        #expect(tester.isEmptySpace(at: emptyPoint, displayKey: 1, screenMinX: screenMinX,
                                    now: 0.05, freshness: .fresh) == false)
    }

    @Test func freshReadRefreshesTheCacheForLaterHovers() {
        let world = World()
        let tester = make(world)
        _ = tester.isEmptySpace(at: emptyPoint, displayKey: 1, screenMinX: screenMinX, now: 0, freshness: .cached)
        world.menuFrame = CGRect(x: 100, y: 0, width: 400, height: 24)
        _ = tester.isEmptySpace(at: emptyPoint, displayKey: 1, screenMinX: screenMinX, now: 0.1, freshness: .fresh)
        // The hover right after the click sees the fresh value without another query.
        let calls = world.menuCalls
        #expect(tester.isEmptySpace(at: newlyAddedMenuPoint, displayKey: 1, screenMinX: screenMinX,
                                    now: 0.12, freshness: .cached) == false)
        #expect(world.menuCalls == calls)
    }

    @Test func invalidateDropsTheCacheForHoverToo() {
        let world = World()
        let tester = make(world)
        _ = tester.isEmptySpace(at: newlyAddedMenuPoint, displayKey: 1, screenMinX: screenMinX,
                                now: 0, freshness: .cached)
        world.menuFrame = CGRect(x: 100, y: 0, width: 400, height: 24)
        tester.invalidate()
        #expect(tester.isEmptySpace(at: newlyAddedMenuPoint, displayKey: 1, screenMinX: screenMinX,
                                    now: 0.01, freshness: .cached) == false)
    }

    @Test func applicationMenuFrameIsExtendedToTheScreenEdge() {
        let world = World()
        world.menuFrame = CGRect(x: 100, y: 0, width: 200, height: 24)
        let tester = make(world)
        // The Apple menu sits left of the app menu's origin: it counts as "inside".
        #expect(tester.isEmptySpace(at: CGPoint(x: 20, y: 10), displayKey: 1, screenMinX: 0,
                                    now: 0, freshness: .fresh) == false)
    }

    @Test func unknownApplicationMenuFrameMeansNotInside() {
        let world = World()
        world.menuFrame = nil
        let tester = make(world)
        #expect(tester.isEmptySpace(at: CGPoint(x: 150, y: 10), displayKey: 1, screenMinX: 0,
                                    now: 0, freshness: .fresh))
    }
}
