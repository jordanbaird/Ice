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
}
