//
//  EventManager.swift
//  Ice
//

import Cocoa
import OSLog

/// Manager for the various event monitors maintained by the app.
@MainActor
final class EventManager {
    private weak var appState: AppState?

    // MARK: - Tasks

    // MARK: Mouse Moved

    private(set) lazy var mouseMovedTask = UniversalEventMonitor.task(for: .mouseMoved) { [weak self] _ in
        guard let self, let appState else {
            return
        }
        guard
            appState.settingsManager.generalSettingsManager.showOnHover,
            !appState.isShowOnHoverPrevented,
            let hiddenSection = appState.menuBarManager.section(withName: .hidden),
            let screen = NSScreen.main
        else {
            return
        }
        if hiddenSection.isHidden {
            guard try isMouseInEmptyMenuBarSpace(of: screen) else {
                return
            }
            try await Task.sleep(for: .seconds(0.2))
            // make sure the mouse is still inside
            guard try isMouseInEmptyMenuBarSpace(of: screen) else {
                return
            }
            hiddenSection.show()
        } else {
            guard isMouseOutsideMenuBar(of: screen) else {
                return
            }
            try await Task.sleep(for: .seconds(0.2))
            // make sure the mouse is still outside
            guard isMouseOutsideMenuBar(of: screen) else {
                return
            }
            hiddenSection.hide()
        }
    } onError: { error in
        Logger.eventManager.error("ERROR: \(error)")
    }

    // MARK: Left Mouse Up

    private(set) lazy var leftMouseUpTask = UniversalEventMonitor.task(for: .leftMouseUp) { [weak appState] _ in
        appState?.menuBarManager.appearanceManager.setIsDraggingMenuBarItem(false)
    }

    // MARK: Smart Rehide

    private(set) lazy var smartRehideTask = UniversalEventMonitor.task(for: .leftMouseDown) { [weak self] _ in
        guard let self, let appState else {
            return
        }

        // make sure auto-rehide is enabled and set to smart
        guard
            appState.settingsManager.generalSettingsManager.autoRehide,
            case .smart = appState.settingsManager.generalSettingsManager.rehideStrategy
        else {
            return
        }

        // make sure the mouse is not in the menu bar
        guard
            let screen = NSScreen.main,
            try !isMouseInMenuBar(of: screen)
        else {
            return
        }

        // get the window that the user has clicked into
        guard
            let hiddenSection = appState.menuBarManager.section(withName: .hidden),
            let mouseLocation = CGEvent(source: nil)?.location,
            let windowUnderMouse = try WindowInfo.getOnScreenWindows(excludeDesktopWindows: true)
                .filter({ $0.windowLayer < CGWindowLevelForKey(.cursorWindow) })
                .first(where: { $0.frame.contains(mouseLocation) }),
            let owningApplication = windowUnderMouse.owningApplication
        else {
            return
        }

        // the dock is an exception to the following check
        if owningApplication.bundleIdentifier != "com.apple.dock" {
            // only continue if the user has clicked into an
            // active window with a regular activation policy
            guard
                owningApplication.isActive,
                owningApplication.activationPolicy == .regular
            else {
                return
            }
        }

        // if all the above checks have passed, hide
        hiddenSection.hide()
    } onError: { error in
        Logger.eventManager.error("ERROR: \(error)")
    }

    // MARK: Show On Click

    private(set) lazy var showOnClickTask = UniversalEventMonitor.task(for: .leftMouseDown) { [weak self] _ in
        guard let self, let appState else {
            return
        }
        guard
            let screen = NSScreen.main,
            let visibleSection = appState.menuBarManager.section(withName: .visible),
            let hiddenSection = appState.menuBarManager.section(withName: .hidden),
            let alwaysHiddenSection = appState.menuBarManager.section(withName: .alwaysHidden)
        else {
            return
        }
        if try isMouseInEmptyMenuBarSpace(of: screen) {
            appState.preventShowOnHover()
            guard appState.settingsManager.generalSettingsManager.showOnClick else {
                return
            }
            if
                NSEvent.modifierFlags == .option,
                appState.settingsManager.advancedSettingsManager.canToggleAlwaysHiddenSection
            {
                try await Task.sleep(for: .seconds(0.05))
                alwaysHiddenSection.toggle()
            } else {
                try await Task.sleep(for: .seconds(0.05))
                hiddenSection.toggle()
            }
        }
    } onError: { error in
        Logger.eventManager.error("ERROR: \(error)")
    }

    // MARK: Prevent Show On Hover

    private(set) lazy var preventShowOnHoverTask = UniversalEventMonitor.task(for: [.leftMouseDown, .rightMouseDown]) { [weak self] _ in
        guard let self, let appState else {
            return
        }
        guard
            let screen = NSScreen.main,
            try isMouseInMenuBarItem(of: screen),
            let visibleSection = appState.menuBarManager.section(withName: .visible),
            let visibleControlItemFrame = visibleSection.controlItem.windowFrame,
            appState.menuBarManager.sections.contains(where: { !$0.isHidden }) || visibleControlItemFrame.contains(NSEvent.mouseLocation)
        else {
            return
        }
        appState.preventShowOnHover()
    } onError: { error in
        Logger.eventManager.error("ERROR: \(error)")
    }

    // MARK: Right Mouse Down

    private(set) lazy var rightMouseDownTask = UniversalEventMonitor.task(for: .rightMouseDown) { [weak self] _ in
        guard let self, let appState else {
            return
        }
        guard
            let screen = NSScreen.main,
            try isMouseInEmptyMenuBarSpace(of: screen)
        else {
            return
        }
        appState.preventShowOnHover()
        appState.menuBarManager.showRightClickMenu(at: NSEvent.mouseLocation)
    } onError: { error in
        Logger.eventManager.error("ERROR: \(error)")
    }

    // MARK: Left Mouse Dragged

    private(set) lazy var leftMouseDraggedTask = UniversalEventMonitor.task(for: .leftMouseDragged) { [weak self] event in
        guard let self, let appState else {
            return
        }
        guard
            event.modifierFlags.contains(.command),
            let screen = NSScreen.main,
            try isMouseInMenuBar(of: screen)
        else {
            return
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
    } onError: { error in
        Logger.eventManager.error("ERROR: \(error)")
    }

    // MARK: Scroll Wheel

    private(set) lazy var scrollWheelTask = UniversalEventMonitor.task(for: .scrollWheel) { [weak self] event in
        guard let self, let appState else {
            return
        }
        guard
            appState.settingsManager.generalSettingsManager.showOnScroll,
            let screen = NSScreen.main,
            try isMouseInMenuBar(of: screen),
            let hiddenSection = appState.menuBarManager.section(withName: .hidden)
        else {
            return
        }
        let averageDelta = (event.scrollingDeltaX + event.scrollingDeltaY) / 2
        if averageDelta > 5 {
            hiddenSection.show()
        } else if averageDelta < -5 {
            hiddenSection.hide()
        }
    } onError: { error in
        Logger.eventManager.error("ERROR: \(error)")
    }

    // MARK: - Initializers

    init(appState: AppState) {
        self.appState = appState
    }

    // MARK: - Setup

    func performSetup() {
        _ = mouseMovedTask
        _ = leftMouseUpTask
        _ = smartRehideTask
        _ = showOnClickTask
        _ = preventShowOnHoverTask
        _ = rightMouseDownTask
        _ = leftMouseDraggedTask
        _ = scrollWheelTask
    }

    // MARK: - Helpers

    private func isMouseInMenuBar(of screen: NSScreen) throws -> Bool {
        if NSApp.presentationOptions.contains(.autoHideMenuBar) {
            if let mouseLocation = CGEvent(source: nil)?.location {
                let menuBar = try WindowInfo.getMenuBarWindow(for: screen.displayID)
                return menuBar.frame.contains(mouseLocation)
            }
        }
        let mouseY = NSEvent.mouseLocation.y
        return mouseY > screen.visibleFrame.maxY && mouseY <= screen.frame.maxY
    }

    private func isMouseInApplicationMenu(of screen: NSScreen) throws -> Bool {
        guard
            try isMouseInMenuBar(of: screen),
            let applicationMenuFrame = appState?.menuBarManager.applicationMenuFrame(for: screen)
        else {
            return false
        }
        return (applicationMenuFrame.minX...applicationMenuFrame.maxX).contains(NSEvent.mouseLocation.x)
    }

    private func isMouseInMenuBarItem(of screen: NSScreen) throws -> Bool {
        guard
            let appState,
            try isMouseInMenuBar(of: screen),
            let mouseLocation = CGEvent(source: nil)?.location
        else {
            return false
        }
        return try appState.menuBarManager.itemManager
            .getMenuBarItems(for: screen.displayID, onScreenOnly: true)
            .contains { item in
                item.frame.contains(mouseLocation)
            }
    }

    private func isMouseInEmptyMenuBarSpace(of screen: NSScreen) throws -> Bool {
        guard
            try isMouseInMenuBar(of: screen),
            try !isMouseInApplicationMenu(of: screen),
            try !isMouseInMenuBarItem(of: screen)
        else {
            return false
        }
        return true
    }

    private func isMouseOutsideMenuBar(of screen: NSScreen) -> Bool {
        let mouseY = NSEvent.mouseLocation.y
        return mouseY < screen.visibleFrame.maxY || mouseY > screen.frame.maxY
    }
}

// MARK: - Logger
private extension Logger {
    static let eventManager = Logger(category: "EventManager")
}
