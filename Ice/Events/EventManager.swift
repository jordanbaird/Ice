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

    // MARK: Show On Click

    private(set) lazy var showOnClickMonitor = UniversalEventMonitor(
        mask: .leftMouseDown
    ) { [weak self] event in
        guard
            let self,
            let appState
        else {
            return event
        }

        // make sure the "ShowOnClick" feature is enabled
        guard appState.settingsManager.generalSettingsManager.showOnClick else {
            return event
        }

        // make sure the mouse is inside an empty menu bar space
        guard isMouseInsideEmptyMenuBarSpace() else {
            return event
        }

        Task {
            // short delay helps the toggle action feel more natural
            try await Task.sleep(for: .milliseconds(50))

            if
                NSEvent.modifierFlags == .option,
                appState.settingsManager.advancedSettingsManager.canToggleAlwaysHiddenSection
            {
                if let alwaysHiddenSection = appState.menuBarManager.section(withName: .alwaysHidden) {
                    alwaysHiddenSection.toggle()
                }
            } else {
                if let hiddenSection = appState.menuBarManager.section(withName: .hidden) {
                    hiddenSection.toggle()
                }
            }
        }

        return event
    }

    // MARK: Show On Hover

    private(set) lazy var showOnHoverMonitor = UniversalEventMonitor(
        mask: .mouseMoved
    ) { [weak self] event in
        guard
            let self,
            let appState
        else {
            return event
        }

        // make sure the "ShowOnHover" feature is enabled and not prevented
        guard
            appState.settingsManager.generalSettingsManager.showOnHover,
            !appState.isShowOnHoverPrevented
        else {
            return event
        }

        // only continue if we have a hidden section (we should)
        guard let hiddenSection = appState.menuBarManager.section(withName: .hidden) else {
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

    // MARK: Show On Scroll

    private(set) lazy var showOnScrollMonitor = UniversalEventMonitor(
        mask: .scrollWheel
    ) { [weak self] event in
        guard
            let self,
            let appState
        else {
            return event
        }

        // make sure the "ShowOnScroll" feature is enabled
        guard appState.settingsManager.generalSettingsManager.showOnScroll else {
            return event
        }

        // make sure the mouse is inside the menu bar
        guard isMouseInsideMenuBar() else {
            return event
        }

        // only continue if we have a hidden section (we should)
        guard let hiddenSection = appState.menuBarManager.section(withName: .hidden) else {
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

        // make sure clicking the Ice Bar doesn't trigger rehide
        guard event.window !== appState.menuBarManager.iceBarPanel else {
            return event
        }

        // only continue if the "hidden" section is currently visible
        guard
            let hiddenSection = appState.menuBarManager.section(withName: .hidden),
            !hiddenSection.isHidden
        else {
            return event
        }

        // make sure the mouse is not in the menu bar
        guard !isMouseInsideMenuBar() else {
            return event
        }

        Task {
            do {
                // sleep for a bit to give the window under the mouse a chance to focus
                try await Task.sleep(for: .seconds(0.25))

                // get the window that the user has clicked into
                guard
                    let mouseLocation = self.getMouseLocation(flipped: true),
                    let windowUnderMouse = try WindowInfo.getOnScreenWindows(excludeDesktopWindows: false)
                        .filter({ $0.layer < CGWindowLevelForKey(.cursorWindow) })
                        .first(where: { $0.frame.contains(mouseLocation) }),
                    let owningApplication = windowUnderMouse.owningApplication
                else {
                    return
                }

                // the dock is an exception to the following check
                if owningApplication.bundleIdentifier != "com.apple.dock" {
                    // only continue if the user has clicked into an active window with
                    // a regular activation policy
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

    // MARK: Prevent Show On Hover

    private(set) lazy var preventShowOnHoverMonitor = UniversalEventMonitor(
        mask: [.leftMouseDown, .rightMouseDown]
    ) { [weak self] event in
        guard
            let self,
            let appState
        else {
            return event
        }

        // make sure the "ShowOnHover" feature is enabled
        guard appState.settingsManager.generalSettingsManager.showOnHover else {
            return event
        }

        // make sure the mouse is inside the menu bar
        guard isMouseInsideMenuBar() else {
            return event
        }

        if isMouseInsideMenuBarItem() {
            switch event.type {
            case .leftMouseDown:
                if appState.menuBarManager.sections.contains(where: { !$0.isHidden }) || isMouseInsideIceIcon {
                    // we have a left click that is inside the menu bar while
                    // at least one section is visible or the mouse is inside
                    // the Ice icon
                    appState.preventShowOnHover()
                }
            case .rightMouseDown:
                if appState.menuBarManager.sections.contains(where: { !$0.isHidden }) {
                    // we have a right click that is inside the menu bar while
                    // at least one section is visible
                    appState.preventShowOnHover()
                }
            default:
                break
            }
        } else if !isMouseInsideApplicationMenu() {
            // we have a left or right click that is inside the menu bar, outside
            // a menu bar item, and outside the application menu, so it _must_ be
            // inside an empty menu bar space
            appState.preventShowOnHover()
        }

        return event
    }

    // MARK: Show Right Click Menu

    private(set) lazy var showRightClickMenuMonitor = UniversalEventMonitor(
        mask: .rightMouseDown
    ) { [weak self] event in
        guard
            let self,
            let appState
        else {
            return event
        }

        // make sure the mouse is inside an empty menu bar space
        guard isMouseInsideEmptyMenuBarSpace() else {
            return event
        }

        if let mouseLocation = getMouseLocation(flipped: false) {
            appState.menuBarManager.showRightClickMenu(at: mouseLocation)
        }

        return event
    }

    // MARK: Left Mouse Dragged

    private(set) lazy var leftMouseDraggedMonitor = UniversalEventMonitor(
        mask: .leftMouseDragged
    ) { [weak self] event in
        guard
            let self,
            let appState
        else {
            return event
        }

        // don't continue if using the Ice Bar
        guard !appState.settingsManager.generalSettingsManager.useIceBar else {
            return event
        }

        // make sure the command key is down
        guard event.modifierFlags.contains(.command) else {
            return event
        }

        // make sure the mouse is inside the menu bar
        guard isMouseInsideMenuBar() else {
            return event
        }

        // notify each overlay panel that a menu bar item is being dragged
        appState.menuBarManager.appearanceManager.setIsDraggingMenuBarItem(true)

        // show all items, including section dividers
        for section in appState.menuBarManager.sections {
            section.show()
            guard
                section.controlItem.isSectionDivider,
                !section.controlItem.isVisible
            else {
                continue
            }
            section.controlItem.isVisible = true
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

    // MARK: - All Monitors

    private lazy var allMonitors = [
        showOnClickMonitor,
        showOnHoverMonitor,
        showOnScrollMonitor,
        smartRehideMonitor,
        preventShowOnHoverMonitor,
        showRightClickMenuMonitor,
        leftMouseDraggedMonitor,
        leftMouseUpMonitor,
    ]

    // MARK: - Initializers

    init(appState: AppState) {
        self.appState = appState
    }

    // MARK: - Start/Stop

    func startAll() {
        for monitor in allMonitors {
            monitor.start()
        }
    }

    func stopAll() {
        for monitor in allMonitors {
            monitor.stop()
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
            let screen,
            let mouseLocation = getMouseLocation(flipped: true),
            let menuBarManager = appState?.menuBarManager,
            let menuFrame = menuBarManager.getStoredApplicationMenuFrame(for: screen.displayID)
        else {
            return false
        }
        return menuFrame.contains(mouseLocation)
    }

    private func isMouseInsideMenuBarItem(ofScreen screen: NSScreen? = .main) -> Bool {
        guard
            let screen,
            let mouseLocation = getMouseLocation(flipped: true)
        else {
            return false
        }
        let menuBarItems = MenuBarItem.getMenuBarItems(for: screen.displayID, onScreenOnly: true)
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

    var isMouseInsideIceIcon: Bool {
        guard
            let appState,
            let visibleSection = appState.menuBarManager.section(withName: .visible),
            let iceIconFrame = visibleSection.controlItem.windowFrame,
            let mouseLocation = getMouseLocation(flipped: false)
        else {
            return false
        }
        return iceIconFrame.contains(mouseLocation)
    }
}

// MARK: - Logger
private extension Logger {
    static let eventManager = Logger(category: "EventManager")
}
