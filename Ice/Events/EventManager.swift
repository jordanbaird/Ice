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
            let display = DisplayInfo.main
        else {
            return
        }
        if hiddenSection.isHidden {
            guard try await isMouseInEmptyMenuBarSpace(of: display) else {
                return
            }
            try await Task.sleep(for: .seconds(0.2))
            // make sure the mouse is still inside
            guard try await isMouseInEmptyMenuBarSpace(of: display) else {
                return
            }
            hiddenSection.show()
        } else {
            guard isMouseOutsideMenuBar(of: display) else {
                return
            }
            try await Task.sleep(for: .seconds(0.2))
            // make sure the mouse is still outside
            guard isMouseOutsideMenuBar(of: display) else {
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
            let display = DisplayInfo.main,
            try await !isMouseInMenuBar(of: display)
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
            let display = DisplayInfo.main,
            let visibleSection = appState.menuBarManager.section(withName: .visible),
            let hiddenSection = appState.menuBarManager.section(withName: .hidden),
            let alwaysHiddenSection = appState.menuBarManager.section(withName: .alwaysHidden)
        else {
            return
        }
        if try await isMouseInEmptyMenuBarSpace(of: display) {
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
            NSEvent.mouseLocation.x - display.bounds.origin.x > appState.menuBarManager.applicationMenuFrame.maxX,
            try await isMouseInMenuBar(of: display)
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
            let display = DisplayInfo.main,
            try await isMouseInEmptyMenuBarSpace(of: display)
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
            let display = DisplayInfo.main,
            try await isMouseInMenuBar(of: display)
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
            let display = DisplayInfo.main,
            try await isMouseInMenuBar(of: display),
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

    private func isMouseInMenuBar(of display: DisplayInfo) async throws -> Bool {
        if NSApp.presentationOptions.contains(.autoHideMenuBar) {
            if let mouseLocation = CGEvent(source: nil)?.location {
                let menuBar = try await WindowInfo.menuBarWindow(for: display)
                return menuBar.frame.contains(mouseLocation)
            }
        }
        if let screen = display.nsScreen {
            let mouseY = NSEvent.mouseLocation.y
            return mouseY > screen.visibleFrame.maxY && mouseY <= screen.frame.maxY
        }
        return false
    }

    private func isMouseInEmptyMenuBarSpace(of display: DisplayInfo) async throws -> Bool {
        guard
            let appState,
            try await isMouseInMenuBar(of: display)
        else {
            return false
        }
        let items = try await appState.menuBarManager.itemManager.menuBarItems(for: display, onScreenOnly: true)
        let totalWidth = items.reduce(into: 0) { width, item in
            width += item.frame.width
        }
        let applicationMenuMaxX = appState.menuBarManager.applicationMenuFrame.maxX
        let mouseX = NSEvent.mouseLocation.x
        return mouseX - display.bounds.origin.x > applicationMenuMaxX && mouseX < display.bounds.maxX - totalWidth
    }

    private func isMouseOutsideMenuBar(of display: DisplayInfo) -> Bool {
        guard let screen = display.nsScreen else {
            return false
        }
        let mouseY = NSEvent.mouseLocation.y
        return mouseY < screen.visibleFrame.maxY || mouseY > screen.frame.maxY
    }
}

// MARK: - Logger
private extension Logger {
    static let eventManager = Logger(category: "EventManager")
}
