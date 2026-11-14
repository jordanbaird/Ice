//
//  MenuBarSpacerPlan.swift
//  Ice
//

import Cocoa

/// Sizes the blank spacers that hide a section on macOS 27.
///
/// Hiding works by widening a divider until it no longer fits in the free
/// part of the menu bar: macOS then moves it, and every item to its left,
/// into overflow. Two limits apply (measured on macOS 27.0.1):
///
/// - A status item whose window (length + 16pt padding) is wider than half
///   the screen is dropped instead of overflowing, so nothing hides. The old
///   "screen width minus app menu" estimate broke every screen without a
///   notch this way (issues #12, #17, #24).
/// - On a wide screen the free space can be larger than that cap, so one
///   spacer fits and hides nothing. Several adjacent spacers add up instead:
///   the ones that fit stay blank, the first one that doesn't overflows and
///   takes the section with it.
enum MenuBarSpacerPlan {
    /// The geometry of one screen that matters for sizing.
    struct Screen: Equatable {
        /// The screen's width, in points.
        var width: CGFloat
        /// The width of the area right of the notch, if the screen has one.
        var auxiliaryRightWidth: CGFloat?
    }

    /// Padding macOS adds around a status item's length.
    static let itemPadding: CGFloat = 16

    /// Extra margin below the drop threshold.
    static let safetyMargin: CGFloat = 8

    /// Width the always-visible items (Control Center, clock) take at least.
    static let minimumVisibleWidth: CGFloat = 48

    /// Upper bound on spacers per divider.
    static let maximumCount = 6

    /// Room the primary display needs left of its status items before Ice
    /// probes there with a divider that overflows on it (see
    /// `ControlItem.primaryStatusItems()`). Wider than nearly any icon,
    /// so no icon right of the divider overflows before the divider does.
    static let minimumProbeRoom: CGFloat = 96

    /// The widest spacer macOS keeps on the given screen.
    static func maxLength(for screen: Screen) -> CGFloat {
        let halfScreenCap = (screen.width / 2).rounded(.down) - itemPadding - safetyMargin
        var length = halfScreenCap
        if let rightWidth = screen.auxiliaryRightWidth, rightWidth.isFinite, rightWidth > 64 {
            // Proven value on notched screens: just under the area right of
            // the notch, which is all the room status items get there.
            length = min(length, rightWidth - 32)
        }
        return max(32, length)
    }

    /// The length of each spacer and how many a divider needs.
    ///
    /// Status items appear on every display's menu bar, so the length must be
    /// kept on the narrowest screen and the count must cover the widest one.
    static func plan(for screens: [Screen]) -> (length: CGFloat, count: Int) {
        let usable = screens.filter { $0.width.isFinite && $0.width > 0 }
        guard !usable.isEmpty else {
            return (1_000, 1)
        }
        let length = usable.map(maxLength(for:)).min() ?? 1_000
        return (length, count(for: usable, length: length))
    }

    /// How many spacers of `length` it takes to fill the widest of `screens`.
    static func count(for screens: [Screen], length: CGFloat) -> Int {
        guard length > 0 else {
            return 1
        }
        let count = screens.filter { $0.width.isFinite && $0.width > 0 }.map { screen -> Int in
            let region = screen.auxiliaryRightWidth ?? screen.width
            let free = max(0, region - minimumVisibleWidth)
            return Int((free / length).rounded(.up))
        }.max() ?? 1
        return min(max(1, count), maximumCount)
    }

    /// Margin past the point where the last extension would just fit.
    static let extensionMargin: CGFloat = 24

    /// Lengths of the blank items that extend a divider, nearest it first,
    /// so that it hides its section on every target screen.
    ///
    /// When the active app's menus are on a screen, macOS squeezes them,
    /// down to little more than the app name, before it moves a status item
    /// into overflow. A blank run that only just fills the free space
    /// therefore eats the menus instead of hiding anything (seen with Ghostty
    /// on a 1920pt display). So the last item is as wide as every target
    /// allows and can't fit even with the menus squeezed to nothing; the
    /// items before it are only as wide as that takes, which leaves the
    /// menus about half the screen.
    ///
    /// - Parameters:
    ///   - dividerLength: The divider's own spacer length.
    ///   - visibleWidth: Width of the items right of the divider.
    ///   - targets: Screens that may show the divider.
    /// - Returns: No lengths when the divider overflows on every target.
    static func extensionLengths(dividerLength: CGFloat, visibleWidth: CGFloat, targets: [Screen]) -> [CGFloat] {
        let dividerWidth = dividerLength + itemPadding
        // Screens where the divider itself still fits, menus squeezed or not.
        let fitting = targets.filter { screen in
            screen.width.isFinite && screen.width > 0 && region(of: screen) - visibleWidth - dividerWidth > 0
        }
        guard let last = fitting.map(maxLength(for:)).min() else {
            return []
        }
        let lastWidth = last + itemPadding
        // Blank width needed right of the last item so it can't fit anywhere.
        let needed = fitting.map { region(of: $0) - visibleWidth - lastWidth + extensionMargin }.max() ?? 0
        var missing = needed - dividerWidth
        var lengths = [CGFloat]()
        while missing > itemPadding, lengths.count < maximumCount - 1 {
            let length = min(missing - itemPadding, last).rounded(.up)
            lengths.append(length)
            missing -= length + itemPadding
        }
        return lengths + [last]
    }

    /// The part of a screen's menu bar that status items can use.
    private static func region(of screen: Screen) -> CGFloat {
        screen.auxiliaryRightWidth ?? screen.width
    }

    /// The plan for the screens currently attached.
    @MainActor
    static func current() -> (length: CGFloat, count: Int) {
        plan(for: NSScreen.screens.map(Screen.init))
    }
}

extension MenuBarSpacerPlan.Screen {
    /// The geometry of an attached screen.
    @MainActor
    init(_ screen: NSScreen) {
        self.init(width: screen.frame.width, auxiliaryRightWidth: screen.auxiliaryTopRightArea?.width)
    }
}

/// Order keys for menu bar items on macOS 27.
///
/// MenuBarAgent sorts trailing items by a per-item order key (larger is
/// further left; the clock is 0). A value in an app's own
/// `NSStatusItem Preferred Position <name>` default seeds the key of a
/// status item that has none yet, and removing the item deletes its key.
/// The stored keys live in a group container that other apps may not read,
/// so Ice never knows a key the user set by dragging; it can only seed its
/// own items and probe where they land.
enum MenuBarOrderHints {
    /// Seeds for a fresh install.
    ///
    /// The old 0/1/2 seeds put both dividers right of nearly every icon, so a
    /// fresh install hid almost the whole bar (issue #17). Now the dividers
    /// start left of everything (nothing hidden until icons are dragged past
    /// them) and the Ice icon starts next to the clock, where it is never
    /// pushed into overflow.
    static func freshSeed(for identifier: ControlItem.Identifier) -> CGFloat {
        switch identifier {
        case .iceIcon: 0.5
        case .hidden: 100_000
        case .alwaysHidden: 100_010
        }
    }

    /// Largest key the spacer probe tries before giving up.
    static let probeLimit: CGFloat = 4_000_000

    /// Precision of the spacer probe. Real keys sit at least 0.5 apart.
    static let probePrecision: CGFloat = 0.01
}
