//
//  EventManager.swift
//  Ice
//

import Cocoa
import OSLog

/// Manager for the various event monitors maintained by the app.
final class EventManager {
    /// A method used to retrieve the mouse location.
    enum MouseLocationMethod {
        /// The mouse location is retrieved using `NSEvent`'s method.
        /// It is based on screen coordinates, with the origin at the
        /// bottom left of the screen.
        case nsEvent
        /// The mouse location is retrieved using `CGEvent`'s method.
        /// It is based on display coordinates, with the origin at the
        /// top left of the display.
        case cgEvent
    }

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
            !appState.showOnHoverIsPreventedByUserInteraction
        else {
            return event
        }
        Task {
            guard
                let display = DisplayInfo.main,
                let hiddenSection = appState.menuBarManager.section(withName: .hidden)
            else {
                return
            }
            do {
                if hiddenSection.isHidden {
                    guard try await self.isMouseInEmptyMenuBarSpace(of: display) else {
                        return
                    }
                    try await Task.sleep(for: .seconds(0.2))
                    // make sure the mouse is still inside
                    guard try await self.isMouseInEmptyMenuBarSpace(of: display) else {
                        return
                    }
                    await hiddenSection.show()
                } else {
                    guard self.isMouseOutsideMenuBar(of: display) else {
                        return
                    }
                    try await Task.sleep(for: .seconds(0.2))
                    // make sure the mouse is still outside
                    guard self.isMouseOutsideMenuBar(of: display) else {
                        return
                    }
                    await hiddenSection.hide()
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
    ) { [weak self, weak appState] event in
        guard
            let self,
            let appState
        else {
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

        Task {
            do {
                // make sure the mouse is not in the menu bar
                guard
                    let display = DisplayInfo.main,
                    try await !self.isMouseInMenuBar(of: display)
                else {
                    return
                }

                // get the window that the user has clicked into
                guard
                    let hiddenSection = appState.menuBarManager.section(withName: .hidden),
                    let mouseLocation = self.getMouseLocation(using: .cgEvent),
                    let windowUnderMouse = try await WindowInfo.current(option: .optionOnScreenOnly)
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

                try await Task.sleep(for: .seconds(0.25))

                // if all the above checks have passed, hide
                await hiddenSection.hide()
            } catch {
                Logger.eventManager.error("ERROR: \(error)")
            }
        }

        return event
    }

    // MARK: Left Mouse Down
    private(set) lazy var leftMouseDownMonitor = UniversalEventMonitor(
        mask: .leftMouseDown
    ) { [weak self, weak appState] event in
        guard
            let self,
            let appState
        else {
            return event
        }
        Task {
            guard
                let display = DisplayInfo.main,
                let visibleSection = appState.menuBarManager.section(withName: .visible),
                let hiddenSection = appState.menuBarManager.section(withName: .hidden),
                let alwaysHiddenSection = appState.menuBarManager.section(withName: .alwaysHidden)
            else {
                return
            }
            do {
                if try await self.isMouseInEmptyMenuBarSpace(of: display) {
                    appState.showOnHoverIsPreventedByUserInteraction = true
                    if appState.settingsManager.generalSettingsManager.showOnClick {
                        if
                            NSEvent.modifierFlags == .option,
                            appState.settingsManager.advancedSettingsManager.canToggleAlwaysHiddenSection
                        {
                            try await Task.sleep(for: .seconds(0.05))
                            await alwaysHiddenSection.toggle()
                        } else {
                            try await Task.sleep(for: .seconds(0.05))
                            await hiddenSection.toggle()
                        }
                    }
                } else if
                    let mouseLocation = self.getMouseLocation(using: .nsEvent),
                    mouseLocation.x - display.frame.origin.x > appState.menuBarManager.applicationMenuFrame.maxX,
                    try await self.isMouseInMenuBar(of: display)
                {
                    appState.showOnHoverIsPreventedByUserInteraction = true
                } else if
                    let mouseLocation = self.getMouseLocation(using: .nsEvent),
                    let visibleControlItemFrame = await visibleSection.controlItem.windowFrame,
                    visibleControlItemFrame.contains(mouseLocation)
                {
                    appState.showOnHoverIsPreventedByUserInteraction = true
                }
            } catch {
                Logger.eventManager.error("ERROR: \(error)")
            }
        }
        return event
    }

    // MARK: Right Mouse Down
    private(set) lazy var rightMouseDownMonitor = UniversalEventMonitor(
        mask: .rightMouseDown
    ) { [weak self, weak appState] event in
        guard
            let self,
            let appState
        else {
            return event
        }
        Task {
            guard let display = DisplayInfo.main else {
                return
            }
            do {
                if
                    try await self.isMouseInEmptyMenuBarSpace(of: display),
                    let mouseLocation = self.getMouseLocation(using: .nsEvent)
                {
                    appState.showOnHoverIsPreventedByUserInteraction = true
                    await appState.menuBarManager.showRightClickMenu(at: mouseLocation)
                }
            } catch {
                Logger.eventManager.error("ERROR: \(error)")
            }
        }
        return event
    }

    // MARK: Left Mouse Dragged
    private(set) lazy var leftMouseDraggedMonitor = UniversalEventMonitor(
        mask: .leftMouseDragged
    ) { [weak self, weak appState] event in
        guard
            let self,
            let appState,
            event.modifierFlags.contains(.command)
        else {
            return event
        }
        Task { @MainActor in
            do {
                guard
                    let display = DisplayInfo.main,
                    try await self.isMouseInMenuBar(of: display)
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
            } catch {
                Logger.eventManager.error("ERROR: \(error)")
            }
        }
        return event
    }

    // MARK: Scroll Wheel
    private(set) lazy var scrollWheelMonitor = UniversalEventMonitor(
        mask: .scrollWheel
    ) { [weak self, weak appState] event in
        guard
            let self,
            let appState,
            appState.settingsManager.generalSettingsManager.showOnScroll
        else {
            return event
        }
        let averageDelta = (event.scrollingDeltaX + event.scrollingDeltaY) / 2
        Task {
            do {
                guard
                    let display = DisplayInfo.main,
                    try await self.isMouseInMenuBar(of: display),
                    let hiddenSection = appState.menuBarManager.section(withName: .hidden)
                else {
                    return
                }
                if averageDelta > 5 {
                    await hiddenSection.show()
                } else if averageDelta < -5 {
                    await hiddenSection.hide()
                }
            } catch {
                Logger.eventManager.error("ERROR: \(error)")
            }
        }
        return event
    }

    // MARK: -

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

    private func getMouseLocation(using method: MouseLocationMethod) -> CGPoint? {
        switch method {
        case .nsEvent: NSEvent.mouseLocation
        case .cgEvent: CGEvent(source: nil)?.location
        }
    }

    private func isMouseInMenuBar(of display: DisplayInfo) async throws -> Bool {
        if await NSApp.presentationOptions.contains(.autoHideMenuBar) {
            if
                let mouseLocation = getMouseLocation(using: .cgEvent),
                let menuBar = try await WindowInfo.menuBarWindow(for: display)
            {
                return menuBar.frame.contains(mouseLocation)
            }
        }
        if
            let screen = display.getNSScreen(),
            let mouseY = getMouseLocation(using: .nsEvent)?.y
        {
            return mouseY > screen.visibleFrame.maxY && mouseY <= screen.frame.maxY
        }
        return false
    }

    private func isMouseInEmptyMenuBarSpace(of display: DisplayInfo) async throws -> Bool {
        guard
            let appState,
            let mouseX = getMouseLocation(using: .nsEvent)?.x,
            try await isMouseInMenuBar(of: display)
        else {
            return false
        }
        let items = try await appState.menuBarManager.itemManager.menuBarItems(for: display, onScreenOnly: true)
        let totalWidth = items.reduce(into: 0) { width, item in
            width += item.frame.width
        }
        let applicationMenuMaxX = appState.menuBarManager.applicationMenuFrame.maxX
        return mouseX - display.frame.origin.x > applicationMenuMaxX && mouseX < display.frame.maxX - totalWidth
    }

    private func isMouseOutsideMenuBar(of display: DisplayInfo) -> Bool {
        guard
            let screen = display.getNSScreen(),
            let mouseY = getMouseLocation(using: .nsEvent)?.y
        else {
            return false
        }
        return mouseY < screen.visibleFrame.maxY || mouseY > screen.frame.maxY
    }
}

// MARK: - Logger
private extension Logger {
    static let eventManager = Logger(category: "EventManager")
}
