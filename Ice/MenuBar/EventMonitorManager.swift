//
//  EventMonitorManager.swift
//  Ice
//

import Cocoa

/// Manager for the various event monitors maintained by the app.
final class EventMonitorManager {
    private weak var menuBarManager: MenuBarManager?

    // MARK: - Monitors

    // MARK: Mouse Moved
    private(set) lazy var mouseMovedMonitor = UniversalEventMonitor(
        mask: .mouseMoved
    ) { [weak menuBarManager] event in
        guard
            let menuBarManager,
            menuBarManager.showOnHover,
            !menuBarManager.showOnHoverPreventedByUserInteraction,
            let screen = NSScreen.main,
            let hiddenSection = menuBarManager.section(withName: .hidden)
        else {
            return event
        }

        func isMouseInEmptyMenuBarSpace() -> Bool {
            guard
                screen.isMouseInMenuBar,
                let controlItemPosition = hiddenSection.controlItem.position
            else {
                return false
            }
            return NSEvent.mouseLocation.x - screen.frame.origin.x > menuBarManager.mainMenuMaxX &&
            screen.frame.maxX - NSEvent.mouseLocation.x > controlItemPosition
        }

        func isMouseOutsideMenuBar() -> Bool {
            NSEvent.mouseLocation.y < screen.visibleFrame.maxY ||
            NSEvent.mouseLocation.y > screen.frame.maxY
        }

        if hiddenSection.isHidden {
            if isMouseInEmptyMenuBarSpace() {
                // small delay for better user experience
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                    // make sure the mouse is still inside
                    if isMouseInEmptyMenuBarSpace() {
                        hiddenSection.show()
                    }
                }
            }
        } else {
            if isMouseOutsideMenuBar() {
                // small delay for better user experience
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

    // MARK: Left Mouse Up
    private(set) lazy var leftMouseUpMonitor = UniversalEventMonitor(
        mask: .leftMouseUp
    ) { [weak menuBarManager] event in
        guard let menuBarManager else {
            return event
        }

        // mouse up means dragging has stopped
        menuBarManager.appearanceManager.setIsDraggingMenuBarItem(false)

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
            let mouseLocation = CGEvent(source: nil)?.location,
            let windowUnderMouse = WindowInfo.getCurrent(option: .optionOnScreenOnly)
                .filter({ $0.windowLayer < CGWindowLevelForKey(.cursorWindow) })
                .first(where: { $0.frame.contains(mouseLocation) }),
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

    // MARK: Left Mouse Down
    private(set) lazy var leftMouseDownMonitor = UniversalEventMonitor(
        mask: .leftMouseDown
    ) { [weak menuBarManager] event in
        guard
            let menuBarManager,
            let screen = NSScreen.main,
            let visibleSection = menuBarManager.section(withName: .visible),
            let hiddenSection = menuBarManager.section(withName: .hidden),
            let alwaysHiddenSection = menuBarManager.section(withName: .alwaysHidden)
        else {
            return event
        }

        func check(section: MenuBarSection) -> Bool {
            if let controlItemPosition = section.controlItem.position {
                NSEvent.mouseLocation.x - screen.frame.origin.x > menuBarManager.mainMenuMaxX &&
                screen.frame.maxX - NSEvent.mouseLocation.x > controlItemPosition
            } else {
                false
            }
        }

        func isMouseInEmptyMenuBarSpace() -> Bool {
            guard screen.isMouseInMenuBar else {
                return false
            }
            return if hiddenSection.isHidden {
                check(section: hiddenSection)
            } else {
                check(section: alwaysHiddenSection)
            }
        }

        if isMouseInEmptyMenuBarSpace() {
            menuBarManager.showOnHoverPreventedByUserInteraction = true
            if menuBarManager.showOnClick {
                // small delay for better user experience
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                    if hiddenSection.isHidden {
                        hiddenSection.show()
                    } else {
                        alwaysHiddenSection.show()
                    }
                }
            }
        } else if check(section: hiddenSection) {
            menuBarManager.showOnHoverPreventedByUserInteraction = true
        } else if
            let visibleControlItemFrame = visibleSection.controlItem.windowFrame,
            visibleControlItemFrame.contains(NSEvent.mouseLocation)
        {
            menuBarManager.showOnHoverPreventedByUserInteraction = true
        }

        return event
    }

    // MARK: Right Mouse Down
    private(set) lazy var rightMouseDownMonitor = UniversalEventMonitor(
        mask: .rightMouseDown
    ) { [weak menuBarManager] event in
        guard let menuBarManager else {
            return event
        }

        func handleSection(_ section: MenuBarSection) {
            guard
                let screen = NSScreen.main,
                let controlItemPosition = section.controlItem.position,
                NSEvent.mouseLocation.x - screen.frame.origin.x > menuBarManager.mainMenuMaxX,
                let screen = NSScreen.main,
                screen.isMouseInMenuBar,
                screen.frame.maxX - NSEvent.mouseLocation.x > controlItemPosition
            else {
                return
            }
            menuBarManager.showOnHoverPreventedByUserInteraction = true
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

    // MARK: Left Mouse Dragged
    private(set) lazy var leftMouseDraggedMonitor = UniversalEventMonitor(
        mask: .leftMouseDragged
    ) { [weak menuBarManager] event in
        guard
            let menuBarManager,
            event.modifierFlags.contains(.command),
            let screen = NSScreen.main,
            screen.isMouseInMenuBar
        else {
            return event
        }
        menuBarManager.showAllSections()
        menuBarManager.appearanceManager.setIsDraggingMenuBarItem(true)
        return event
    }

    // MARK: --

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
