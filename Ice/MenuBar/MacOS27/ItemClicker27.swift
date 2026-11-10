//
//  ItemClicker27.swift
//  Ice
//

import AppKit
import ApplicationServices
import OSLog

/// Opens a hidden item's menu from the Ice Bar on macOS 27.
///
/// Ice can no longer move an item into view. Its application is allowed for a moment, and
/// the drawn item is clicked where it appears, the way Ice clicks items on earlier macOS,
/// with the pointer put back afterwards. An item that is not drawn, such as one folded
/// behind the overflow button, is pressed through Accessibility. Menus open on the display
/// with the active menu bar, so if that is not the Ice Bar's display, Ice first clicks the
/// empty spot of that display's menu bar where the Ice Bar was opened (measured on
/// macOS 27.0: that click makes the menu bar active). The click comes before the
/// application is shown, while the spot is still empty.
@available(macOS 27.0, *)
@MainActor
enum ItemClicker27 {
    private static let logger = Logger(category: "ItemClicker27")

    /// How long Ice waits for an item to be published after its application is allowed.
    ///
    /// Measured 2026-11-04: Docker Desktop's item was published 0.7 s after the switch went
    /// back on. The wait is longer than that because it costs nothing when the item is already
    /// there, and a click that opens nothing is worse than one that takes a moment.
    private static let publishTimeout = Duration.seconds(3)

    static func click(item: MenuBarItem, mouseButton: CGMouseButton, iceBarDisplayID: CGDirectDisplayID?, appState: AppState) async {
        guard let bundleID = item.sourceApplication?.bundleIdentifier else {
            logger.error("No application for \(item.logString, privacy: .public)")
            return
        }

        if
            ItemClick27.needsMenuBarActivation(activeDisplayID: Bridging.getActiveMenuBarDisplayID(), iceBarDisplayID: iceBarDisplayID),
            let iceBarDisplayID,
            let point = appState.hidEventManager.lastEmptyMenuBarPoint(for: iceBarDisplayID)
        {
            postMenuBarActivationClick(at: point)
            try? await Task.sleep(for: .milliseconds(300))
        }

        let concealer = appState.concealer27
        var drawn = await concealer.showTemporarily(bundleID: bundleID, untilDrawn: item.windowID)
        var expandedOverflow = false
        if drawn == nil {
            drawn = await expandSystemOverflow(for: item, bundleID: bundleID, concealer: concealer)
            expandedOverflow = drawn != nil
        }

        let ownerPID = item.ownerPID
        let baseline = Set(windowOwners().map { $0.number })
        if let drawn {
            postClick(at: CGPoint(x: drawn.bounds.midX, y: drawn.bounds.midY), mouseButton: mouseButton)
        } else if let element = await MenuBarItemProvider27.element(forWindowID: item.windowID, waitingUpTo: Self.publishTimeout) {
            // Hardly any item answers AXShowMenu: of the thirteen on this Mac only DockDoor's
            // did, and the other twelve offer AXPress alone (measured 2026-11-04). A right click
            // that asked for a menu the item does not have simply did nothing, so it presses
            // instead, which is what a right click on most of them does anyway.
            var action = kAXPressAction
            if mouseButton == .right {
                action = await actionNames(of: element).contains(kAXShowMenuAction) ? kAXShowMenuAction : kAXPressAction
            }
            // A press that opens a menu answers only once the menu closes, so the messaging
            // timeout set for the scan runs out first and the action is reported as not
            // completed although it took effect (measured 2026-11-04 on Pritunl's item). How
            // long it took is what tells the two apart, so both are recorded.
            let started = ContinuousClock.now
            let result = await perform(action, on: element)
            logger.notice(
                """
                \(action, privacy: .public) on \(item.logString, privacy: .public) \
                returned \(result.rawValue, privacy: .public) after \(ContinuousClock.now - started, privacy: .public)
                """
            )
        } else {
            logger.error(
                """
                \(item.logString, privacy: .public) is neither drawn nor reachable through Accessibility: \
                its application publishes no item of its own, which on macOS 27 only relaunching it cures
                """
            )
            concealer.endTemporaryShow(bundleID: bundleID)
            return
        }

        // A click returns at once, and a press blocks only while a menu is open. Keep the
        // application shown until the menu or panel that opened is gone.
        try? await Task.sleep(for: .milliseconds(400))
        var waited = 0
        while waited < 240, ItemClick27.interfaceIsOpen(windowOwners: windowOwners(), ownerPID: ownerPID, baseline: baseline) {
            try? await Task.sleep(for: .milliseconds(250))
            waited += 1
        }
        concealer.endTemporaryShow(bundleID: bundleID)
        if expandedOverflow {
            await collapseSystemOverflow()
        }
    }

    /// How long Ice waits for a folded item to be drawn once the overflow is expanded.
    ///
    /// Measured 2026-11-04: an item folded into the overflow was laid out beside the notch
    /// 0.17 s after the press, and stayed drawn for the twelve seconds the measurement ran.
    private static let unfoldTimeout = Duration.seconds(2)

    /// Expands the system overflow, so that an item folded into it is drawn, and answers it.
    ///
    /// This is what the user does by hand when an item will not fit: press the ">>" at the left
    /// of the run, and the item appears past the notch, where it is visible and clickable. Ice
    /// has to do it because a folded item is out of reach otherwise — its application publishes
    /// no item at all through Accessibility while it is folded, so there is nothing to click and
    /// nothing to press (measured 2026-11-04 on Docker Desktop, whose process answered
    /// `kAXErrorNoValue` for the whole of a 4.5 s wait while the overflow control stood on the
    /// bar beside it).
    ///
    /// ``collapseSystemOverflow()`` puts the bar back once the menu is gone.
    private static func expandSystemOverflow(for item: MenuBarItem, bundleID: String, concealer: Concealer27) async -> MenuBarItem? {
        let displayID = Bridging.getActiveMenuBarDisplayID()
        guard let indicator = MenuBarItemProvider27.overflowIndicator(for: displayID, expanded: false) else {
            return nil
        }
        let result = await perform(kAXPressAction, on: indicator.element)
        logger.notice(
            """
            Expanded the system overflow at x=\(indicator.frame.minX, privacy: .public) \
            to reach \(item.logString, privacy: .public): AXPress returned \(result.rawValue, privacy: .public)
            """
        )
        guard result == .success else {
            return nil
        }
        return await concealer.drawnItem(
            bundleID: bundleID,
            windowID: item.windowID,
            floor: .zero,
            timeout: Self.unfoldTimeout,
            acrossNotchIsFinal: false
        )
    }

    /// Collapses an overflow Ice expanded, once the item is concealed again.
    ///
    /// Left alone, macOS collapses it itself, but takes its time over it: measured 2026-11-04,
    /// the overflow Ice had expanded was still open 75 s later and closed somewhere before 93 s.
    /// All that while the bar stands rearranged, its items pushed past the notch.
    ///
    /// Often there is nothing to do: with the item concealed again the overflow usually has
    /// nothing left to hold and closes by itself, and the control is then gone from the bar.
    private static func collapseSystemOverflow() async {
        try? await Task.sleep(for: .milliseconds(400))
        // Twice at most: a press that did not take leaves the bar standing rearranged, and a
        // bar left expanded was seen once (2026-11-04) after a press that answered success.
        for attempt in 1...2 {
            _ = await MenuBarItemProvider27.items()
            guard
                let indicator = MenuBarItemProvider27.overflowIndicator(
                    for: Bridging.getActiveMenuBarDisplayID(),
                    expanded: true
                )
            else {
                return
            }
            let result = await perform(kAXPressAction, on: indicator.element)
            logger.notice(
                """
                Collapsed the system overflow again, attempt \(attempt, privacy: .public): \
                AXPress returned \(result.rawValue, privacy: .public)
                """
            )
            try? await Task.sleep(for: .milliseconds(300))
        }
    }

    private static func actionNames(of element: AXUIElement) async -> [String] {
        await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                var names: CFArray?
                guard AXUIElementCopyActionNames(element, &names) == .success else {
                    continuation.resume(returning: [])
                    return
                }
                continuation.resume(returning: (names as? [String]) ?? [])
            }
        }
    }

    private static func perform(_ action: String, on element: AXUIElement) async -> AXError {
        await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                continuation.resume(returning: AXUIElementPerformAction(element, action as CFString))
            }
        }
    }

    private static func windowOwners() -> [(number: Int, ownerPID: Int32)] {
        let windows = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]] ?? []
        return windows.compactMap { window in
            guard
                let number = window[kCGWindowNumber as String] as? Int,
                let pid = window[kCGWindowOwnerPID as String] as? Int32
            else {
                return nil
            }
            return (number: number, ownerPID: pid)
        }
    }

    private static func postMenuBarActivationClick(at point: CGPoint) {
        postClick(at: point, mouseButton: .left)
    }

    /// Posts a click marked so that Ice's own mouse handlers ignore it, then puts the pointer back.
    private static func postClick(at point: CGPoint, mouseButton: CGMouseButton) {
        let source = CGEventSource(stateID: .hidSystemState)
        let original = CGEvent(source: nil)?.location
        let types: [CGEventType] = mouseButton == .right ? [.rightMouseDown, .rightMouseUp] : [.leftMouseDown, .leftMouseUp]
        for type in types {
            guard let event = CGEvent(mouseEventSource: source, mouseType: type, mouseCursorPosition: point, mouseButton: mouseButton) else {
                continue
            }
            event.setIntegerValueField(.eventSourceUserData, value: HIDEventManager.menuBarActivationMarker)
            event.post(tap: .cghidEventTap)
        }
        if let original {
            _ = CGWarpMouseCursorPosition(original)
        }
    }
}
