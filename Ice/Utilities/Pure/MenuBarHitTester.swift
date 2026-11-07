//
//  MenuBarHitTester.swift
//  Ice
//

import CoreGraphics

/// Tells whether a point in the menu bar is over the application menu or a
/// menu bar item, with a short-lived cache for mouse *movement* and a
/// mandatory fresh read for *click* decisions.
///
/// The application menu frame (Accessibility) and the item bounds (window
/// server) are IPC calls. Hover handlers run on every mouse-moved event, so
/// they use ``Freshness/cached`` (250 ms for items, 500 ms for the menu).
/// A click decides whether to toggle a section or open a context menu, and
/// the geometry can change without any notification (the app's menu grows
/// with a document or a modal), so clicks use ``Freshness/fresh``, which
/// also refreshes the cache.
final class MenuBarHitTester {
    enum Freshness {
        /// May reuse a recent value (movement).
        case cached
        /// Reads again (click decisions).
        case fresh
    }

    private let applicationMenuFrame: (UInt32) -> CGRect?
    private let itemBounds: () -> [CGRect]
    private let menuTTL: Double
    private let itemsTTL: Double
    private var menuMemos = [UInt32: TimedMemo<CGRect?>]()
    private var itemsMemo: TimedMemo<[CGRect]>

    init(
        applicationMenuFrame: @escaping (UInt32) -> CGRect?,
        itemBounds: @escaping () -> [CGRect],
        menuTTL: Double = 0.5,
        itemsTTL: Double = 0.25
    ) {
        self.applicationMenuFrame = applicationMenuFrame
        self.itemBounds = itemBounds
        self.menuTTL = menuTTL
        self.itemsTTL = itemsTTL
        self.itemsMemo = TimedMemo(ttl: itemsTTL)
    }

    /// Drops every cached value.
    func invalidate() {
        menuMemos.removeAll()
        itemsMemo.invalidate()
    }

    /// Drops only the cached item bounds.
    func invalidateItems() {
        itemsMemo.invalidate()
    }

    /// Returns whether the point is over the application menu (extended to
    /// the screen's left edge, so the Apple menu counts) .
    func isInsideApplicationMenu(
        _ point: CGPoint,
        displayKey: UInt32,
        screenMinX: CGFloat,
        now: Double,
        freshness: Freshness
    ) -> Bool {
        var memo = menuMemos[displayKey] ?? TimedMemo<CGRect?>(ttl: menuTTL)
        if freshness == .fresh {
            memo.invalidate()
        }
        let frame = memo.value(now: now) { applicationMenuFrame(displayKey) }
        menuMemos[displayKey] = memo
        guard var frame else {
            return false
        }
        frame.size.width += frame.origin.x - screenMinX
        frame.origin.x = screenMinX
        return frame.contains(point)
    }

    /// Returns whether the point is over a menu bar item.
    func isInsideItem(_ point: CGPoint, now: Double, freshness: Freshness) -> Bool {
        if freshness == .fresh {
            itemsMemo.invalidate()
        }
        return itemsMemo.value(now: now, compute: itemBounds).contains { $0.contains(point) }
    }

    /// Returns whether the point is over neither the application menu nor an item.
    func isEmptySpace(
        at point: CGPoint,
        displayKey: UInt32,
        screenMinX: CGFloat,
        now: Double,
        freshness: Freshness
    ) -> Bool {
        !isInsideApplicationMenu(point, displayKey: displayKey, screenMinX: screenMinX, now: now, freshness: freshness) &&
        !isInsideItem(point, now: now, freshness: freshness)
    }
}
