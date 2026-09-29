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
        concealer.showTemporarily(bundleID: bundleID)
        // A shown item is drawn 0.4–0.6 s after its application is allowed (measured).
        try? await Task.sleep(for: .milliseconds(600))

        let ownerPID = item.ownerPID
        let baseline = Set(windowOwners().map { $0.number })
        let drawn = await MenuBarItemProvider27.items().first { $0.windowID == item.windowID && $0.isOnScreen }
        if let drawn {
            postClick(at: CGPoint(x: drawn.bounds.midX, y: drawn.bounds.midY), mouseButton: mouseButton)
        } else if let element = MenuBarItemProvider27.element(forWindowID: item.windowID) {
            let action = mouseButton == .right ? kAXShowMenuAction : kAXPressAction
            let result = await perform(action, on: element)
            if result != .success {
                logger.notice("\(action, privacy: .public) on \(item.logString, privacy: .public) returned \(result.rawValue, privacy: .public)")
            }
        } else {
            logger.error("\(item.logString, privacy: .public) is neither drawn nor reachable through Accessibility")
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
