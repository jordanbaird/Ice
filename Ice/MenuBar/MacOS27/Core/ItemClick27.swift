//
//  ItemClick27.swift
//  Ice
//

import CoreGraphics

/// Pure rules for clicking an item from the Ice Bar on macOS 27.
enum ItemClick27 {
    /// Whether the menu bar of the Ice Bar's display must be made active first: an
    /// item's menu opens on the display with the active menu bar (measured on macOS 27.0).
    static func needsMenuBarActivation(activeDisplayID: CGDirectDisplayID?, iceBarDisplayID: CGDirectDisplayID?) -> Bool {
        guard let iceBarDisplayID else {
            return false
        }
        return activeDisplayID != iceBarDisplayID
    }

    /// The window a system item's panel opened in, if one appeared.
    ///
    /// Both panels stand at or above the menu bar's level and are tall, which the ordinary
    /// windows that may open at the same moment are not (measured on macOS 27.0: Control
    /// Centre opens "Control Center", layer 101, 656×964, about 177 ms after the press, and
    /// the clock opens "Notification Center", layer 21, the size of the display, about 166 ms
    /// after the click — a level an earlier version of this rule was too high to notice, so
    /// Notification Center counted as never opening).
    static func panelWindow(before: Set<Int>, windows: [(number: Int, layer: Int, height: CGFloat)]) -> Int? {
        windows.first { window in
            !before.contains(window.number) && window.layer >= panelLayer && window.height > panelHeight
        }?.number
    }

    /// Whether a system item's panel opened, judged by the windows on screen.
    static func panelOpened(before: Set<Int>, windows: [(number: Int, layer: Int, height: CGFloat)]) -> Bool {
        panelWindow(before: before, windows: windows) != nil
    }

    /// The window of a system item's panel that is already on screen, if one is.
    ///
    /// The caller must pass only the windows of the processes that draw those panels. Every
    /// window at this level and size is not a panel: the Dock's window stands at layer 20 and
    /// the size of the display and never goes away, so with it in the list every click looked
    /// like a click that closes a panel (measured on macOS 27.0).
    ///
    /// A click that lands while a panel is up is the click that closes it. Putting concealment
    /// back stalls MenuBarAgent for 100 to 150 ms (measured on macOS 27.0, against the moment
    /// each assertion was applied), and in the middle of a closing animation that shows as a
    /// lag — so a click that closes a panel waits for the panel to be gone first.
    static func openPanelWindow(windows: [(number: Int, layer: Int, height: CGFloat)]) -> Int? {
        panelWindow(before: [], windows: windows)
    }

    /// Whether the panel that opened in the given window is still on screen.
    static func panelIsOnScreen(window: Int, windows: [(number: Int, layer: Int, height: CGFloat)]) -> Bool {
        windows.contains { $0.number == window }
    }

    /// The level the panels stand at: the menu bar's own level and above.
    private static let panelLayer = 20

    /// Taller than the menu bar's own windows, so the bar never passes for a panel.
    private static let panelHeight: CGFloat = 150

    static func interfaceIsOpen(windowOwners: [(number: Int, ownerPID: Int32)], ownerPID: Int32, baseline: Set<Int>) -> Bool {
        windowOwners.contains { $0.ownerPID == ownerPID && !baseline.contains($0.number) }
    }
}
