//
//  NotchClickResolver.swift
//  Ice
//

import CoreGraphics

/// Decides whether a mouse click toggles the Trincano Bar because it landed
/// on a notch.
///
/// The screen is chosen by the **click point**, never by `NSScreen.main`
/// (which is the screen with keyboard focus): with the focus on an external
/// monitor, a click on the notebook's notch must still count.
enum NotchClickResolver {
    struct Screen {
        let frame: CGRect
        let notch: NotchGeometry?
    }

    enum Decision: Equatable {
        case none
        case toggleBar(screenIndex: Int)
    }

    /// - Parameters:
    ///   - point: The click location, in global AppKit coordinates.
    ///   - screens: Every screen's frame and notch, in the same coordinates.
    ///   - isEnabled: The user setting.
    ///   - isLeftButton: Only a left click toggles the bar.
    static func resolve(
        point: CGPoint,
        screens: [Screen],
        isEnabled: Bool,
        isLeftButton: Bool
    ) -> Decision {
        guard
            isEnabled,
            isLeftButton,
            let index = screenIndex(containing: point, in: screens.map(\.frame)),
            let notch = screens[index].notch,
            NotchClickPolicy.shouldToggleBar(isEnabled: isEnabled, hasNotch: true, clickIsInsideNotch: notch.contains(point))
        else {
            return .none
        }
        return .toggleBar(screenIndex: index)
    }

    /// Returns the screen that contains the point: strictly inside first, then
    /// counting the top and right edges (the pointer can sit exactly there).
    static func screenIndex(containing point: CGPoint, in frames: [CGRect]) -> Int? {
        if let strict = frames.firstIndex(where: { $0.contains(point) }) {
            return strict
        }
        return frames.firstIndex { frame in
            point.x >= frame.minX && point.x <= frame.maxX &&
            point.y >= frame.minY && point.y <= frame.maxY
        }
    }

    /// Decides from a mouse-down delivery.
    ///
    /// - Parameters:
    ///   - eventLocation: Where the mouse-down happened (the event's own
    ///     location), or `nil` if the event has none.
    ///   - cursorLocation: Where the cursor is when the event is delivered. It
    ///     is deliberately **not** used: a delayed event would be judged by
    ///     where the cursor is now instead of where the click happened. Without
    ///     an event location the notch action is ignored.
    static func decide(
        eventLocation: CGPoint?,
        cursorLocation: CGPoint,
        screens: [Screen],
        isEnabled: Bool,
        isLeftButton: Bool
    ) -> Decision {
        _ = cursorLocation
        guard let eventLocation else {
            return .none
        }
        return resolve(point: eventLocation, screens: screens, isEnabled: isEnabled, isLeftButton: isLeftButton)
    }
}
