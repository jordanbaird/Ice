//
//  EventManager.swift
//  Ice
//

import Cocoa

/// Manager for the various event monitors maintained by the app.
final class EventManager {
    private weak var appState: AppState?

    // MARK: - Monitors

    // MARK: Mouse Moved
    private(set) lazy var mouseMovedMonitor = UniversalEventMonitor(
        mask: .mouseMoved
    ) { [weak self, weak appState] event in
        guard
            let self,
            let appState,
            appState.settingsManager.generalSettingsManager.showOnHover,
            !appState.showOnHoverPreventedByUserInteraction,
            let display = DisplayInfo.main,
            let hiddenSection = appState.menuBarManager.section(withName: .hidden)
        else {
            return event
        }

        if hiddenSection.isHidden {
            if isMouseInEmptyMenuBarSpace(of: display) {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                    // make sure the mouse is still inside
                    if self.isMouseInEmptyMenuBarSpace(of: display) {
                        hiddenSection.show()
                    }
                }
            }
        } else {
            if isMouseOutsideMenuBar(of: display) {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                    // make sure the mouse is still outside
                    if self.isMouseOutsideMenuBar(of: display) {
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
    ) { [weak appState] event in
        guard let appState else {
            return event
        }

        // mouse up means dragging has stopped
        appState.menuBarManager.appearanceManager.setIsDraggingMenuBarItem(false)

        // make sure auto-rehide is enabled and set to smart
        guard
            appState.settingsManager.generalSettingsManager.autoRehide,
            case .smart = appState.settingsManager.generalSettingsManager.rehideStrategy
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
            let hiddenSection = appState.menuBarManager.section(withName: .hidden),
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
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) {
            hiddenSection.hide()
        }

        return event
    }

    // MARK: Left Mouse Down
    private(set) lazy var leftMouseDownMonitor = UniversalEventMonitor(
        mask: .leftMouseDown
    ) { [weak self, weak appState] event in
        guard
            let self,
            let appState,
            let display = DisplayInfo.main,
            let visibleSection = appState.menuBarManager.section(withName: .visible),
            let hiddenSection = appState.menuBarManager.section(withName: .hidden),
            let alwaysHiddenSection = appState.menuBarManager.section(withName: .alwaysHidden)
        else {
            return event
        }

        if isMouseInEmptyMenuBarSpace(of: display) {
            appState.showOnHoverPreventedByUserInteraction = true
            if appState.settingsManager.generalSettingsManager.showOnClick {
                if
                    NSEvent.modifierFlags == .option,
                    appState.settingsManager.advancedSettingsManager.canToggleAlwaysHiddenSection
                {
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                        alwaysHiddenSection.toggle()
                    }
                } else {
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                        hiddenSection.toggle()
                    }
                }
            }
        } else if
            NSEvent.mouseLocation.x - display.frame.origin.x > appState.menuBarManager.mainMenuMaxX,
            isMouseInMenuBar(of: display)
        {
            appState.showOnHoverPreventedByUserInteraction = true
        } else if
            let visibleControlItemFrame = visibleSection.controlItem.windowFrame,
            visibleControlItemFrame.contains(NSEvent.mouseLocation)
        {
            appState.showOnHoverPreventedByUserInteraction = true
        }

        return event
    }

    // MARK: Right Mouse Down
    private(set) lazy var rightMouseDownMonitor = UniversalEventMonitor(
        mask: .rightMouseDown
    ) { [weak self, weak appState] event in
        guard
            let self,
            let appState,
            let display = DisplayInfo.main
        else {
            return event
        }

        if isMouseInEmptyMenuBarSpace(of: display) {
            appState.showOnHoverPreventedByUserInteraction = true
            appState.menuBarManager.showRightClickMenu(at: NSEvent.mouseLocation)
        }

        return event
    }

    // MARK: Left Mouse Dragged
    private(set) lazy var leftMouseDraggedMonitor = UniversalEventMonitor(
        mask: .leftMouseDragged
    ) { [weak appState] event in
        guard
            let appState,
            event.modifierFlags.contains(.command),
            let screen = NSScreen.main,
            screen.isMouseInMenuBar
        else {
            return event
        }
        if appState.settingsManager.advancedSettingsManager.showSectionDividers {
            for section in appState.menuBarManager.sections where section.isHidden {
                section.show()
            }
        } else {
            for section in appState.menuBarManager.sections {
                if section.isHidden {
                    section.show()
                }
                if
                    section.controlItem.isSectionDivider,
                    !section.controlItem.isVisible
                {
                    section.controlItem.isVisible = true
                }
            }
        }
        appState.menuBarManager.appearanceManager.setIsDraggingMenuBarItem(true)
        return event
    }

    // MARK: Scroll Wheel
    private(set) lazy var scrollWheelMonitor = UniversalEventMonitor(
        mask: .scrollWheel
    ) { [weak appState] event in
        guard
            let appState,
            appState.settingsManager.generalSettingsManager.showOnScroll,
            let screen = NSScreen.main,
            screen.isMouseInMenuBar,
            let hiddenSection = appState.menuBarManager.section(withName: .hidden)
        else {
            return event
        }
        if (event.scrollingDeltaX + event.scrollingDeltaY) / 2 > 5 {
            hiddenSection.show()
        } else if (event.scrollingDeltaX + event.scrollingDeltaY) / 2 < -5 {
            hiddenSection.hide()
        }
        return event
    }

    // MARK: --

    init(appState: AppState) {
        self.appState = appState
    }

    func performSetup() {
        mouseMovedMonitor.start()
        leftMouseUpMonitor.start()
        leftMouseDownMonitor.start()
        rightMouseDownMonitor.start()
        leftMouseDraggedMonitor.start()
        scrollWheelMonitor.start()
    }

    private func isMouseInMenuBar(of display: DisplayInfo) -> Bool {
        if NSApp.presentationOptions.contains(.autoHideMenuBar) {
            if
                let mouseLocation = CGEvent(source: nil)?.location,
                let menuBar = appState?.menuBarManager.itemManager.getMenuBarWindow(for: display)
            {
                return menuBar.frame.contains(mouseLocation)
            }
        }
        if let screen = display.getNSScreen() {
            let mouseLocation = NSEvent.mouseLocation
            return mouseLocation.y > screen.visibleFrame.maxY && mouseLocation.y <= screen.frame.maxY
        }
        return false
    }

    private func isMouseInEmptyMenuBarSpace(of display: DisplayInfo) -> Bool {
        guard
            let appState,
            isMouseInMenuBar(of: display)
        else {
            return false
        }
        let items = appState.menuBarManager.itemManager.getMenuBarItems(for: display, onScreenOnly: true)
        let totalWidth = items.reduce(into: 0) { width, item in
            width += item.frame.width
        }
        let mouseLocation = NSEvent.mouseLocation
        return mouseLocation.x - display.frame.origin.x > appState.menuBarManager.mainMenuMaxX
            && mouseLocation.x < display.frame.maxX - totalWidth
    }

    private func isMouseOutsideMenuBar(of display: DisplayInfo) -> Bool {
        guard let screen = display.getNSScreen() else {
            return false
        }
        let mouseLocation = NSEvent.mouseLocation
        return mouseLocation.y < screen.visibleFrame.maxY || mouseLocation.y > screen.frame.maxY
    }
}
