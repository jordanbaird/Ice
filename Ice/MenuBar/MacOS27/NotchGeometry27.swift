//
//  NotchGeometry27.swift
//  Ice
//

import Cocoa

/// Where a display's notch cuts its menu bar.
///
/// Status items are laid out from the right edge of the bar, and once they no longer fit in the
/// run beside the notch macOS puts them elsewhere: folded into its own overflow, which
/// `OverflowDetection27` recognises, or further left. An item laid out across the notch is still
/// reported through Accessibility, with a frame, but it is drawn on nothing and a click at that
/// frame lands on nothing. One laid out past the notch, among the application menus, is drawn
/// and can be clicked, which is why only the notch's own span counts here (measured on
/// macOS 27.2, built-in display 1512 points wide: the notch spans 664 to 848, and the item
/// Ice revealed for a click was put at 602 to 648, right beside it).
///
/// The screen list is read on the main thread and kept here, because the item scan that needs
/// it runs on its own queue.
@available(macOS 27.0, *)
enum NotchGeometry27 {
    private static let lock = NSLock()
    nonisolated(unsafe) private static var rangesByDisplay = [CGDirectDisplayID: ClosedRange<CGFloat>]()

    /// Reads the current screen layout.
    @MainActor
    static func refresh() {
        let measured = NSScreen.screens.reduce(into: [CGDirectDisplayID: ClosedRange<CGFloat>]()) { result, screen in
            // `frameOfNotch` is `nil` on a display that has none.
            guard let notch = screen.frameOfNotch, notch.width > 0 else {
                return
            }
            result[screen.displayID] = notch.minX...notch.maxX
        }
        lock.withLock { rangesByDisplay = measured }
    }

    /// The span the given display's notch covers, or `nil` for a display with no notch.
    static func notchXRange(for displayID: CGDirectDisplayID?) -> ClosedRange<CGFloat>? {
        guard let displayID else {
            return nil
        }
        return lock.withLock { rangesByDisplay[displayID] }
    }
}
