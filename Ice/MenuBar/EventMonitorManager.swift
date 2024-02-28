//
//  EventMonitorManager.swift
//  Ice
//

import Cocoa

/// Manager for the various event monitors maintained by the app.
final class EventMonitorManager {
    private weak var menuBarManager: MenuBarManager?

    private(set) lazy var mouseMovedMonitor = UniversalEventMonitor(mask: .mouseMoved) { [weak self] event in
        guard
            let menuBarManager = self?.menuBarManager,
            menuBarManager.showOnHover,
            !menuBarManager.showOnHoverPreventedByUserInteraction,
            let hiddenSection = menuBarManager.section(withName: .hidden)
        else {
            return event
        }

        if hiddenSection.isHidden {
            func isMouseInEmptyMenuBarSpace() -> Bool {
                guard
                    let screen = NSScreen.main,
                    screen.isMouseInMenuBar,
                    let controlItemPosition = hiddenSection.controlItem.position
                else {
                    return false
                }
                return NSEvent.mouseLocation.x > menuBarManager.mainMenuMaxX &&
                screen.frame.maxX - NSEvent.mouseLocation.x > controlItemPosition
            }
            if isMouseInEmptyMenuBarSpace() {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                    // make sure the mouse is still inside
                    if isMouseInEmptyMenuBarSpace() {
                        hiddenSection.show()
                    }
                }
            }
        } else {
            func isMouseOutsideMenuBar() -> Bool {
                guard let screen = NSScreen.main else {
                    return false
                }
                return NSEvent.mouseLocation.y < screen.visibleFrame.maxY ||
                NSEvent.mouseLocation.y > screen.frame.maxY
            }
            if isMouseOutsideMenuBar() {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                    // make sure the mouse is still outside
                    if isMouseOutsideMenuBar() {
                        hiddenSection.hide()
                    }
                }
            }
        }

        return event
    }

    private(set) lazy var leftMouseUpMonitor = UniversalEventMonitor(mask: .leftMouseUp) { [weak self] event in
        guard let menuBarManager = self?.menuBarManager else {
            return event
        }

        // make sure auto-rehide is enabled and set to smart
        guard
            menuBarManager.autoRehide,
            case .smart = menuBarManager.rehideStrategy
        else {
            return event
        }

        // make sure the mouse is not in the menu bar
        guard
            let screen = NSScreen.main,
            !screen.isMouseInMenuBar
        else {
            return event
        }

        // get the window that the user has clicked into
        guard
            let hiddenSection = menuBarManager.section(withName: .hidden),
            let flippedMouseLocation = NSEvent.flippedMouseLocation,
            let windowUnderMouse = WindowInfo.getCurrent(option: .optionOnScreenOnly)
                .filter({ $0.windowLayer < CGWindowLevelForKey(.cursorWindow) })
                .first(where: { $0.frame.contains(flippedMouseLocation) }),
            let owningApplication = windowUnderMouse.owningApplication
        else {
            return event
        }

        // the dock is an exception to the following check
        if owningApplication.bundleIdentifier != "com.apple.dock" {
            // only continue if the user has clicked into an
            // active window with a regular activation policy
            guard
                owningApplication.isActive,
                owningApplication.activationPolicy == .regular
            else {
                return event
            }
        }

        // if all the above checks have passed, hide
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            hiddenSection.hide()
        }

        return event
    }

    private(set) lazy var leftMouseDownMonitor = UniversalEventMonitor(mask: .leftMouseDown) { [weak self] event in
        guard
            let menuBarManager = self?.menuBarManager,
            let visibleSection = menuBarManager.section(withName: .visible),
            let visibleControlItemFrame = visibleSection.controlItem.windowFrame
        else {
            return event
        }

        func isMouseInEmptyMenuBarSpace() -> Bool {
            guard
                let screen = NSScreen.main,
                screen.isMouseInMenuBar,
                let hiddenSection = menuBarManager.section(withName: .hidden),
                let controlItemPosition = hiddenSection.controlItem.position
            else {
                return false
            }
            return NSEvent.mouseLocation.x > menuBarManager.mainMenuMaxX &&
            screen.frame.maxX - NSEvent.mouseLocation.x > controlItemPosition
        }

        if isMouseInEmptyMenuBarSpace() {
            menuBarManager.showOnHoverPreventedByUserInteraction = true
            if
                menuBarManager.showOnClick,
                let hiddenSection = menuBarManager.section(withName: .hidden)
            {
                // small delay for better user experience
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                    hiddenSection.show()
                }
            }
        } else if visibleControlItemFrame.contains(NSEvent.mouseLocation) {
            menuBarManager.showOnHoverPreventedByUserInteraction = true
        }

        return event
    }

    private(set) lazy var rightMouseDownMonitor = UniversalEventMonitor(mask: .rightMouseDown) { [weak self] event in
        guard let menuBarManager = self?.menuBarManager else {
            return event
        }

        func handleSection(_ section: MenuBarSection) {
            guard
                let controlItemPosition = section.controlItem.position,
                NSEvent.mouseLocation.x > menuBarManager.mainMenuMaxX,
                let screen = NSScreen.main,
                screen.isMouseInMenuBar,
                screen.frame.maxX - NSEvent.mouseLocation.x > controlItemPosition
            else {
                return
            }
            menuBarManager.showRightClickMenu(at: NSEvent.mouseLocation)
        }

        if
            let hiddenSection = menuBarManager.section(withName: .hidden),
            hiddenSection.isHidden
        {
            handleSection(hiddenSection)
        } else if
            let alwaysHiddenSection = menuBarManager.section(withName: .alwaysHidden),
            alwaysHiddenSection.isHidden
        {
            handleSection(alwaysHiddenSection)
        }

        return event
    }

    private(set) lazy var leftMouseDraggedMonitor = UniversalEventMonitor(mask: .leftMouseDragged) { [weak self] event in
        guard
            let menuBarManager = self?.menuBarManager,
            event.modifierFlags.contains(.command),
            let screen = NSScreen.main,
            screen.isMouseInMenuBar
        else {
            return event
        }
        menuBarManager.showAllSections()
        return event
    }

    init(menuBarManager: MenuBarManager) {
        self.menuBarManager = menuBarManager
    }

    func performSetup() {
        mouseMovedMonitor.start()
        leftMouseUpMonitor.start()
        leftMouseDownMonitor.start()
        rightMouseDownMonitor.start()
        leftMouseDraggedMonitor.start()
    }
}
