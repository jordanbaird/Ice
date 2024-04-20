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
            !appState.showOnHoverIsPrevented,
            let hiddenSection = appState.menuBarManager.section(withName: .hidden),
            let screen = NSScreen.main
        else {
            return
        }
        if hiddenSection.isHidden {
            guard try await isMouseInEmptyMenuBarSpace(of: screen) else {
                return
            }
            try await Task.sleep(for: .seconds(0.2))
            // make sure the mouse is still inside
            guard try await isMouseInEmptyMenuBarSpace(of: screen) else {
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
            try await !isMouseInMenuBar(of: screen)
        else {
            return
        }

        // get the window that the user has clicked into
        guard
            let hiddenSection = appState.menuBarManager.section(withName: .hidden),
            let mouseLocation = CGEvent(source: nil)?.location,
            let windowUnderMouse = try await WindowInfo.onScreenWindows(excludeDesktopWindows: true)
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
        if try await isMouseInEmptyMenuBarSpace(of: screen) {
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
        } else if
            let display = DisplayInfo(nsScreen: screen),
            let applicationMenuFrame = appState.menuBarManager.applicationMenuFrame(for: display),
            NSEvent.mouseLocation.x - screen.frame.origin.x > applicationMenuFrame.maxX,
            try await isMouseInMenuBar(of: screen)
        {
            appState.preventShowOnHover()
        } else if
            let visibleControlItemFrame = visibleSection.controlItem.windowFrame,
            visibleControlItemFrame.contains(NSEvent.mouseLocation)
        {
            appState.preventShowOnHover()
        }
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
            try await isMouseInEmptyMenuBarSpace(of: screen)
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
            try await isMouseInMenuBar(of: screen)
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
            try await isMouseInMenuBar(of: screen),
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
        _ = rightMouseDownTask
        _ = leftMouseDraggedTask
        _ = scrollWheelTask
    }

    // MARK: - Helpers

    private func isMouseInMenuBar(of screen: NSScreen) async throws -> Bool {
        if NSApp.presentationOptions.contains(.autoHideMenuBar) {
            if
                let mouseLocation = CGEvent(source: nil)?.location,
                let display = DisplayInfo(nsScreen: screen)
            {
                let menuBar = try await WindowInfo.menuBarWindow(for: display)
                return menuBar.frame.contains(mouseLocation)
            }
        }
        let mouseY = NSEvent.mouseLocation.y
        return mouseY > screen.visibleFrame.maxY && mouseY <= screen.frame.maxY
    }

    private func isMouseInEmptyMenuBarSpace(of screen: NSScreen) async throws -> Bool {
        guard
            let appState,
            let display = DisplayInfo(nsScreen: screen),
            try await isMouseInMenuBar(of: screen),
            let applicationMenuFrame = appState.menuBarManager.applicationMenuFrame(for: display)
        else {
            return false
        }
        let items = try await appState.menuBarManager.itemManager.menuBarItems(for: display, onScreenOnly: true)
        let totalWidth = items.reduce(into: 0) { width, item in
            width += item.frame.width
        }
        let mouseX = NSEvent.mouseLocation.x
        return mouseX - screen.frame.origin.x > applicationMenuFrame.maxX && mouseX < screen.frame.maxX - totalWidth
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
