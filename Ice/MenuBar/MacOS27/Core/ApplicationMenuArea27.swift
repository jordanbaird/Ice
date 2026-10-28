//
//  ApplicationMenuArea27.swift
//  Ice
//

import CoreGraphics

/// The stretch of a menu bar the application's own menus occupy.
///
/// Before macOS 27 the menus were read from the display they were asked about, so their frame and
/// that display shared an origin, and widening the frame to the display's left edge was arithmetic
/// on one coordinate space. On 27 they are read from the application that owns the menu bar,
/// wherever it is, so the same frame comes back for every display — in the owning display's
/// coordinates. Widening it against another display's left edge then produces nonsense: a rect
/// stretched across both displays when the owner is to the right, and one of negative width,
/// which contains nothing at all, when the owner is to the left. The second is what reveals the
/// hidden items when the pointer is over the menus of the display that is not active.
///
/// What carries across displays is how far the menus reach from their own display's left edge.
enum ApplicationMenuArea27 {
    /// The menus' stretch of the given display's bar.
    ///
    /// - Parameters:
    ///   - menuFrame: The union of the application's menus, as Accessibility reports it.
    ///   - ownerDisplay: The bounds of the display the menus are drawn on.
    ///   - display: The bounds of the display being asked about.
    ///   - notchGap: How much of the measurement is the owning display's notch rather than menus.
    ///     A long menu bar carries on past a notch and the gap goes into the measurement with it;
    ///     no other display has that gap, so the caller passes it when asking about another one.
    /// How far an application's menus reach, out of what has been measured of them.
    ///
    /// The same display is the exact answer: the same menus, the same bar, the same width. Another
    /// display's measurement of the same application is a good one — its menus are the same, and
    /// only a bar that compresses them, beside a notch, draws them shorter — so the widest is
    /// taken, which errs towards leaving the hover off the titles.
    static func reach(onThisDisplay: CGFloat?, onOtherDisplays: [CGFloat]) -> CGFloat? {
        if let onThisDisplay {
            return onThisDisplay
        }
        return onOtherDisplays.max()
    }

    ///   - barHeight: How tall that display's menu bar is.
    ///   - itemsLeftEdge: The left edge of the leftmost item drawn on that display, when the
    ///     display is not the one the menus were measured on.
    ///   - rememberedReach: How far the menus of the application frontmost on that display reached
    ///     the last time it was the active one there.
    static func area(
        menuFrame: CGRect,
        ownerDisplay: CGRect,
        display: CGRect,
        barHeight: CGFloat,
        notchGap: CGFloat = 0,
        itemsLeftEdge: CGFloat? = nil,
        rememberedReach: CGFloat? = nil
    ) -> CGRect {
        var reach = menuFrame.maxX - ownerDisplay.minX - notchGap
        // A display that is not the one the menus were measured on may be drawing menus of its
        // own: with separate Spaces each display shows the menus of the application frontmost on
        // it, and Accessibility describes only the bar the menus are drawn on — asked about any
        // other display, it answers with that same bar (measured on macOS 27.0). The measurement
        // is therefore of the wrong application's menus, usually too short, and hovering the
        // titles it falls short of revealed the hidden items.
        //
        // Nothing can measure them from here, but they were measurable the last time that
        // application was the active one on that display, and menus of the same application on
        // the same display are the same width. That measurement is exact; the halves below are
        // only for an application that has not been active there yet.
        if let rememberedReach {
            reach = max(reach, rememberedReach)
        } else if let itemsLeftEdge {
            // The line is drawn by halves: the stretch from the display's left edge to its first
            // item is menus for half its length and bare bar for the rest. It keeps the hover off
            // the titles until the exact measurement arrives.
            reach = max(reach, (itemsLeftEdge - display.minX) / 2)
        }
        let width = min(max(reach, 0), display.width)
        // The bar's own top and height, not the menus': displays of different heights put their
        // bars at different places in the global coordinates — the built-in one here starts 98
        // points down — and a rect carrying the other display's y contains nothing on this one.
        return CGRect(x: display.minX, y: display.minY, width: width, height: barHeight)
    }
}
