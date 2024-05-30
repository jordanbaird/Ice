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

    // MARK: - Monitors

    // MARK: Mouse Moved

    private(set) lazy var mouseMovedMonitor = UniversalEventMonitor(
        mask: .mouseMoved
    ) { [weak self] event in
        guard
            let self,
            let appState,
            appState.settingsManager.generalSettingsManager.showOnHover,
            !appState.isShowOnHoverPrevented,
            let hiddenSection = appState.menuBarManager.section(withName: .hidden)
        else {
            return event
        }
        Task {
            do {
                if hiddenSection.isHidden {
                    guard self.isMouseInsideEmptyMenuBarSpace() else {
                        return
                    }
                    try await Task.sleep(for: .seconds(0.2))
                    // make sure the mouse is still inside
                    guard self.isMouseInsideEmptyMenuBarSpace() else {
                        return
                    }
                    hiddenSection.show()
                } else {
                    guard self.isMouseOutsideMenuBar() else {
                        return
                    }
                    try await Task.sleep(for: .seconds(0.2))
                    // make sure the mouse is still outside
                    guard self.isMouseOutsideMenuBar() else {
                        return
                    }
                    hiddenSection.hide()
                }
            } catch {
                Logger.eventManager.error("ERROR: \(error)")
            }
        }
        return event
    }

    // MARK: Left Mouse Up

    private(set) lazy var leftMouseUpMonitor = UniversalEventMonitor(
        mask: .leftMouseUp
    ) { [weak appState] event in
        appState?.menuBarManager.appearanceManager.setIsDraggingMenuBarItem(false)
        return event
    }

    // MARK: Smart Rehide

    private(set) lazy var smartRehideMonitor = UniversalEventMonitor(
        mask: .leftMouseDown
    ) { [weak self] event in
        guard
            let self,
            let appState
        else {
            return event
        }

        // make sure auto-rehide is enabled and set to smart
        guard
            appState.settingsManager.generalSettingsManager.autoRehide,
            case .smart = appState.settingsManager.generalSettingsManager.rehideStrategy
        else {
            return event
        }

        Task {
            do {
                // sleep for a little bit to give the window under
                // the mouse a chance to focus
                try await Task.sleep(for: .milliseconds(10))

                // make sure the mouse is not in the menu bar
                guard !self.isMouseInsideMenuBar() else {
                    return
                }

                // get the window that the user has clicked into
                guard
                    let hiddenSection = appState.menuBarManager.section(withName: .hidden),
                    let mouseLocation = self.getMouseLocation(flipped: true),
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
            } catch {
                Logger.eventManager.error("ERROR: \(error)")
            }
        }

        return event
    }

    // MARK: Show On Click

    private(set) lazy var showOnClickMonitor = UniversalEventMonitor(
        mask: .leftMouseDown
    ) { [weak self] event in
        guard
            let self,
            let appState,
            let visibleSection = appState.menuBarManager.section(withName: .visible),
            let hiddenSection = appState.menuBarManager.section(withName: .hidden),
            let alwaysHiddenSection = appState.menuBarManager.section(withName: .alwaysHidden)
        else {
            return event
        }
        if isMouseInsideEmptyMenuBarSpace() {
            appState.preventShowOnHover()
            guard appState.settingsManager.generalSettingsManager.showOnClick else {
                return event
            }
            if
                NSEvent.modifierFlags == .option,
                appState.settingsManager.advancedSettingsManager.canToggleAlwaysHiddenSection
            {
                Task {
                    try await Task.sleep(for: .seconds(0.05))
                    alwaysHiddenSection.toggle()
                }
            } else {
                Task {
                    try await Task.sleep(for: .seconds(0.05))
                    hiddenSection.toggle()
                }
            }
        }
        return event
    }

    // MARK: Prevent Show On Hover

    private(set) lazy var preventShowOnHoverMonitor = UniversalEventMonitor(
        mask: [.leftMouseDown, .rightMouseDown]
    ) { [weak self] event in
        guard
            let self,
            let appState,
            isMouseInsideMenuBarItem()
        else {
            return event
        }
        switch event.type {
        case .leftMouseDown:
            if
                let visibleSection = appState.menuBarManager.section(withName: .visible),
                let itemFrame = visibleSection.controlItem.windowFrame,
                let mouseLocation = getMouseLocation(flipped: false),
                appState.menuBarManager.sections.contains(where: { !$0.isHidden }) || itemFrame.contains(mouseLocation)
            {
                appState.preventShowOnHover()
            }
        case .rightMouseDown:
            if appState.menuBarManager.sections.contains(where: { !$0.isHidden }) {
                appState.preventShowOnHover()
            }
        default:
            break
        }
        return event
    }

    // MARK: Right Click Menu

    private(set) lazy var rightClickMenuMonitor = UniversalEventMonitor(
        mask: .rightMouseDown
    ) { [weak self] event in
        guard
            let self,
            let appState,
            isMouseInsideEmptyMenuBarSpace(),
            let mouseLocation = getMouseLocation(flipped: false)
        else {
            return event
        }
        appState.preventShowOnHover()
        appState.menuBarManager.showRightClickMenu(at: mouseLocation)
        return event
    }

    // MARK: Left Mouse Dragged

    private(set) lazy var leftMouseDraggedMonitor = UniversalEventMonitor(
        mask: .leftMouseDragged
    ) { [weak self] event in
        guard
            let self,
            let appState,
            event.modifierFlags.contains(.command),
            isMouseInsideMenuBar()
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
    ) { [weak self] event in
        guard
            let self,
            let appState,
            appState.settingsManager.generalSettingsManager.showOnScroll,
            isMouseInsideMenuBar(),
            let hiddenSection = appState.menuBarManager.section(withName: .hidden)
        else {
            return event
        }
        let averageDelta = (event.scrollingDeltaX + event.scrollingDeltaY) / 2
        if averageDelta > 5 {
            hiddenSection.show()
        } else if averageDelta < -5 {
            hiddenSection.hide()
        }
        return event
    }

    // MARK: - All Monitors

    private lazy var allMonitors = [
        mouseMovedMonitor,
        leftMouseUpMonitor,
        smartRehideMonitor,
        showOnClickMonitor,
        preventShowOnHoverMonitor,
        rightClickMenuMonitor,
        leftMouseDraggedMonitor,
        scrollWheelMonitor,
    ]

    // MARK: - Initializers

    init(appState: AppState) {
        self.appState = appState
    }

    // MARK: - Setup

    func performSetup() {
        for monitor in allMonitors {
            monitor.start()
        }
    }

    // MARK: - Helpers

    private func getMouseLocation(flipped: Bool) -> CGPoint? {
        CGEvent(source: nil).map { event in
            if flipped {
                event.location
            } else {
                event.unflippedLocation
            }
        }
    }

    private func isMouseInsideMenuBar(ofScreen screen: NSScreen? = .main) -> Bool {
        guard let screen else {
            return false
        }
        if NSApp.presentationOptions.contains(.autoHideMenuBar) {
            if
                let mouseLocation = getMouseLocation(flipped: true),
                let menuBarWindow = try? WindowInfo.getMenuBarWindow(for: screen.displayID)
            {
                return menuBarWindow.frame.contains(mouseLocation)
            }
        } else {
            if let mouseLocation = getMouseLocation(flipped: false) {
                return mouseLocation.y > screen.visibleFrame.maxY && mouseLocation.y <= screen.frame.maxY
            }
        }
        return false
    }

    private func isMouseInsideApplicationMenu(ofScreen screen: NSScreen? = .main) -> Bool {
        guard
            isMouseInsideMenuBar(ofScreen: screen),
            let screen,
            let mouseLocation = getMouseLocation(flipped: true),
            let menuBarManager = appState?.menuBarManager,
            let menuFrame = menuBarManager.applicationMenuFrame(for: screen.displayID)
        else {
            return false
        }
        return menuFrame.contains(mouseLocation)
    }

    private func isMouseInsideMenuBarItem(ofScreen screen: NSScreen? = .main) -> Bool {
        guard
            isMouseInsideMenuBar(ofScreen: screen),
            let screen,
            let mouseLocation = getMouseLocation(flipped: true),
            let itemManager = appState?.menuBarManager.itemManager,
            let menuBarItems = try? itemManager.getMenuBarItems(for: screen.displayID, onScreenOnly: true)
        else {
            return false
        }
        return menuBarItems.contains { $0.frame.contains(mouseLocation) }
    }

    private func isMouseInsideEmptyMenuBarSpace(ofScreen screen: NSScreen? = .main) -> Bool {
        isMouseInsideMenuBar(ofScreen: screen) &&
        !isMouseInsideApplicationMenu(ofScreen: screen) &&
        !isMouseInsideMenuBarItem(ofScreen: screen)
    }

    private func isMouseOutsideMenuBar(ofScreen screen: NSScreen? = .main) -> Bool {
        guard
            let screen,
            let mouseLocation = getMouseLocation(flipped: false)
        else {
            return false
        }
        return mouseLocation.y < screen.visibleFrame.maxY || mouseLocation.y > screen.frame.maxY
    }
}

// MARK: - Logger
private extension Logger {
    static let eventManager = Logger(category: "EventManager")
}
