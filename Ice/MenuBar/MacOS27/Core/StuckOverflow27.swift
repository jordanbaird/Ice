//
//  StuckOverflow27.swift
//  Ice
//

import CoreGraphics

/// Recognises the notched bar's stuck overflow on macOS 27.
///
/// On the MacBook's built-in display macOS 27 folds items that do not fit beside the notch.
/// Concealing hidden applications frees room, but the visible items it folded are not laid out
/// again: the "<<" button disappears and they are left unreachable (seen on macOS 27.0, see
/// `Scripts/macos27/reflow-probe.swift`). With no overflow button, an item that is laid out
/// never sits under the notch nor on top of another one, so either is a sign of that state.
/// Accessibility keeps the frames of items that are no longer drawn, so the sign is not proof.
enum StuckOverflow27 {
    /// The horizontal span the notch covers on a display, from the widths of the unobscured
    /// areas beside it, or `nil` for a display without a notch.
    static func notchSpan(displayBounds: CGRect, leftAreaWidth: CGFloat?, rightAreaWidth: CGFloat?) -> ClosedRange<CGFloat>? {
        guard let leftAreaWidth, let rightAreaWidth else {
            return nil
        }
        let minX = displayBounds.minX + leftAreaWidth
        let maxX = displayBounds.maxX - rightAreaWidth
        return minX < maxX ? minX...maxX : nil
    }

    /// Whether the visible items on a notched bar look folded with no way to reach them.
    ///
    /// - Parameters:
    ///   - visibleItemFrames: Frames of the items meant to be shown on that bar.
    ///   - chevronFrame: The frame of the overflow button, if there is one.
    ///   - notchSpan: The span the notch covers, see ``notchSpan(displayBounds:leftAreaWidth:rightAreaWidth:)``.
    static func isStuck(visibleItemFrames: [CGRect], chevronFrame: CGRect?, notchSpan: ClosedRange<CGFloat>?) -> Bool {
        guard chevronFrame == nil, let notchSpan else {
            return false
        }
        // Items laid out side by side overlap by 2 points (measured on macOS 27.0); folded
        // items are stacked on one another.
        let tolerance: CGFloat = 6
        let frames = visibleItemFrames.filter { $0.width > 4 }
        let underNotch = frames.contains { frame in
            frame.maxX - tolerance > notchSpan.lowerBound && frame.minX + tolerance < notchSpan.upperBound
        }
        let sorted = frames.sorted { $0.minX < $1.minX }
        let stacked = zip(sorted, sorted.dropFirst()).contains { left, right in
            left.maxX - right.minX > tolerance
        }
        return underNotch || stacked
    }

    /// The entries in a bar's window that belong to applications rather than to the system group.
    ///
    /// MenuBarAgent lists an application's item on the bar it is drawn on with its frame, and on
    /// the other display's bar as an entry with no geometry at all (measured on macOS 27.0). Both
    /// count: what matters is that the bar lists the item, not where it says it is. The system
    /// group — battery, Wi-Fi, Control Centre, clock — sits at the right end, and is left out by
    /// taking only what lies left of it.
    ///
    /// An item folded away beside the notch is listed by neither account, which is what makes a
    /// bar missing items recognisable at all.
    static func applicationEntryCount(childFrames: [CGRect], systemItemFrames: [CGRect]) -> Int {
        guard let systemEdge = systemItemFrames.map(\.minX).min() else {
            return childFrames.count
        }
        return childFrames.filter { $0.width < 1 || $0.minX < systemEdge - 1 }.count
    }

    /// Whether a bar draws fewer application items than there are to draw.
    ///
    /// This is the state on a notched bar that is not the active one, where the geometry
    /// ``isStuck(visibleItemFrames:chevronFrame:notchSpan:)`` reads cannot be had: the items
    /// folded away are simply absent from the bar's window, while the other display draws them.
    static func isStuck(drawnApplicationItems: Int, expectedApplicationItems: Int) -> Bool {
        expectedApplicationItems > 0 && drawnApplicationItems < expectedApplicationItems
    }
}
