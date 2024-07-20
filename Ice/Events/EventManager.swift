//
//  EventManager.swift
//  Ice
//

import Cocoa
import Combine
import OSLog

/// Manager for the various event monitors maintained by the app.
@MainActor
final class EventManager {
    private weak var appState: AppState?

    private var cancellables = Set<AnyCancellable>()

    // MARK: Monitors

    private(set) lazy var mouseDownMonitor = UniversalEventMonitor(
        mask: [.leftMouseDown, .rightMouseDown]
    ) { [weak self] event in
        guard let self else {
            return event
        }
        switch event.type {
        case .leftMouseDown:
            handleShowOnClick()
            handleSmartRehide(with: event)
        case .rightMouseDown:
            handleShowRightClickMenu()
        default:
            break
        }
        handlePreventShowOnHover(with: event)
        return event
    }

    private(set) lazy var mouseUpMonitor = UniversalEventMonitor(
        mask: .leftMouseUp
    ) { [weak self] event in
        self?.handleLeftMouseUp()
        return event
    }

    private(set) lazy var mouseDraggedMonitor = UniversalEventMonitor(
        mask: .leftMouseDragged
    ) { [weak self] event in
        self?.handleLeftMouseDragged(with: event)
        return event
    }

    private(set) lazy var mouseMovedMonitor = UniversalEventMonitor(
        mask: .mouseMoved
    ) { [weak self] event in
        self?.handleShowOnHover()
        return event
    }

    private(set) lazy var scrollWheelMonitor = UniversalEventMonitor(
        mask: .scrollWheel
    ) { [weak self] event in
        self?.handleShowOnScroll(with: event)
        return event
    }

    // MARK: All Monitors

    private lazy var allMonitors = [
        mouseDownMonitor,
        mouseUpMonitor,
        mouseDraggedMonitor,
        mouseMovedMonitor,
        scrollWheelMonitor,
    ]

    // MARK: Initializers

    init(appState: AppState) {
        self.appState = appState
    }

    func performSetup() {
        startAll()
        configureCancellables()
    }

    private func configureCancellables() {
        var c = Set<AnyCancellable>()

        if let appState {
            if let hiddenSection = appState.menuBarManager.section(withName: .hidden) {
                // in fullscreen mode, the menu bar slides down from the top on hover;
                // observe the frame of the only control item we know will always be
                // in the menu bar, and run the show-on-hover check when it changes
                Publishers.CombineLatest(
                    hiddenSection.controlItem.$windowFrame,
                    appState.$isActiveSpaceFullscreen
                )
                .sink { [weak self] _, isFullscreen in
                    guard
                        let self,
                        isFullscreen
                    else {
                        return
                    }
                    handleShowOnHover()
                }
                .store(in: &c)
            }
        }

        cancellables = c
    }

    // MARK: Start/Stop

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
}

// MARK: - Handlers

extension EventManager {

    // MARK: Handle Show On Click

    private func handleShowOnClick() {
        guard
            let appState,
            appState.settingsManager.generalSettingsManager.showOnClick,
            isMouseInsideEmptyMenuBarSpace
        else {
            return
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
    }

    // MARK: Handle Smart Rehide

    private func handleSmartRehide(with event: NSEvent) {
        guard
            let appState,
            appState.settingsManager.generalSettingsManager.autoRehide,
            case .smart = appState.settingsManager.generalSettingsManager.rehideStrategy
        else {
            return
        }

        if let visibleSection = appState.menuBarManager.section(withName: .visible) {
            guard event.window !== visibleSection.controlItem.window else {
                return
            }
        }

        // make sure clicking the Ice Bar doesn't trigger rehide
        guard event.window !== appState.menuBarManager.iceBarPanel else {
            return
        }

        // only continue if a section is currently visible
        guard let shownSection = appState.menuBarManager.shownSection else {
            return
        }

        // make sure the mouse is not in the menu bar
        guard !isMouseInsideMenuBar else {
            return
        }

        Task {
            do {
                let initialSpaceID = Bridging.activeSpaceID

                // sleep for a bit to give the window under the mouse a chance to focus
                try await Task.sleep(for: .seconds(0.25))

                // if clicking caused a space change, don't bother with the window check
                if Bridging.activeSpaceID != initialSpaceID {
                    shownSection.hide()
                    return
                }

                // get the window that the user has clicked into
                guard
                    let mouseLocation = MouseCursor.location(flipped: true),
                    let windowUnderMouse = WindowInfo.getOnScreenWindows(excludeDesktopWindows: false)
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
                shownSection.hide()
            } catch {
                Logger.eventManager.error("ERROR: \(error)")
            }
        }
    }

    // MARK: Handle Show Right Click Menu

    private func handleShowRightClickMenu() {
        guard
            let appState,
            isMouseInsideEmptyMenuBarSpace,
            let mouseLocation = MouseCursor.location(flipped: false)
        else {
            return
        }
        appState.menuBarManager.showRightClickMenu(at: mouseLocation)
    }

    // MARK: Handle Prevent Show On Hover

    private func handlePreventShowOnHover(with event: NSEvent) {
        guard
            let appState,
            appState.settingsManager.generalSettingsManager.showOnHover,
            !appState.settingsManager.generalSettingsManager.useIceBar,
            isMouseInsideMenuBar
        else {
            return
        }

        if isMouseInsideMenuBarItem {
            switch event.type {
            case .leftMouseDown:
                if appState.menuBarManager.sections.contains(where: { !$0.isHidden }) || isMouseInsideIceIcon {
                    // we have a left click that is inside the menu bar while at least one
                    // section is visible or the mouse is inside the Ice icon
                    appState.preventShowOnHover()
                }
            case .rightMouseDown:
                if appState.menuBarManager.sections.contains(where: { !$0.isHidden }) {
                    // we have a right click that is inside the menu bar while at least one
                    // section is visible
                    appState.preventShowOnHover()
                }
            default:
                break
            }
        } else if !isMouseInsideApplicationMenu {
            // we have a left or right click that is inside the menu bar, outside
            // a menu bar item, and outside the application menu, so it _must_ be
            // inside an empty menu bar space
            appState.preventShowOnHover()
        }
    }

    // MARK: Handle Left Mouse Up

    private func handleLeftMouseUp() {
        guard let appearanceManager = appState?.menuBarManager.appearanceManager else {
            return
        }
        appearanceManager.setIsDraggingMenuBarItem(false)
    }

    // MARK: Handle Left Mouse Dragged

    private func handleLeftMouseDragged(with event: NSEvent) {
        guard
            let appState,
            event.modifierFlags.contains(.command),
            isMouseInsideMenuBar
        else {
            return
        }

        // notify each overlay panel that a menu bar item is being dragged
        appState.menuBarManager.appearanceManager.setIsDraggingMenuBarItem(true)

        // stop here if using the Ice Bar
        guard !appState.settingsManager.generalSettingsManager.useIceBar else {
            return
        }

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
    }

    // MARK: Handle Show On Hover

    private func handleShowOnHover() {
        guard let appState else {
            return
        }

        // make sure the "ShowOnHover" feature is enabled and not prevented
        guard
            appState.settingsManager.generalSettingsManager.showOnHover,
            !appState.isShowOnHoverPrevented
        else {
            return
        }

        // only continue if we have a hidden section (we should)
        guard let hiddenSection = appState.menuBarManager.section(withName: .hidden) else {
            return
        }

        Task {
            do {
                if hiddenSection.isHidden {
                    guard self.isMouseInsideEmptyMenuBarSpace else {
                        return
                    }
                    try await Task.sleep(for: .seconds(0.2))
                    // make sure the mouse is still inside
                    guard self.isMouseInsideEmptyMenuBarSpace else {
                        return
                    }
                    hiddenSection.show()
                } else {
                    guard
                        !self.isMouseInsideMenuBar,
                        !self.isMouseInsideIceBar
                    else {
                        return
                    }
                    try await Task.sleep(for: .seconds(0.2))
                    // make sure the mouse is still outside
                    guard
                        !self.isMouseInsideMenuBar,
                        !self.isMouseInsideIceBar
                    else {
                        return
                    }
                    hiddenSection.hide()
                }
            } catch {
                Logger.eventManager.error("ERROR: \(error)")
            }
        }
    }

    // MARK: Handle Show On Scroll

    private func handleShowOnScroll(with event: NSEvent) {
        guard let appState else {
            return
        }

        // make sure the "ShowOnScroll" feature is enabled
        guard appState.settingsManager.generalSettingsManager.showOnScroll else {
            return
        }

        // make sure the mouse is inside the menu bar
        guard isMouseInsideMenuBar else {
            return
        }

        // only continue if we have a hidden section (we should)
        guard let hiddenSection = appState.menuBarManager.section(withName: .hidden) else {
            return
        }

        let averageDelta = (event.scrollingDeltaX + event.scrollingDeltaY) / 2

        if averageDelta > 5 {
            hiddenSection.show()
        } else if averageDelta < -5 {
            hiddenSection.hide()
        }
    }
}

// MARK: - Helpers

extension EventManager {
    /// Returns the best screen to use for event manager calculations.
    var bestScreen: NSScreen? {
        guard let appState else {
            return nil
        }
        if appState.isActiveSpaceFullscreen {
            return NSScreen.screenWithMouse ?? NSScreen.main
        } else {
            return NSScreen.main
        }
    }

    /// A Boolean value that indicates whether the mouse pointer is within
    /// the bounds of the menu bar.
    var isMouseInsideMenuBar: Bool {
        guard
            let screen = bestScreen,
            let appState
        else {
            return false
        }
        if appState.menuBarManager.isMenuBarHiddenBySystem || appState.isActiveSpaceFullscreen {
            if
                let mouseLocation = MouseCursor.location(flipped: true),
                let menuBarWindow = WindowInfo.getMenuBarWindow(for: screen.displayID)
            {
                return menuBarWindow.frame.contains(mouseLocation)
            }
        } else if let mouseLocation = MouseCursor.location(flipped: false) {
            return mouseLocation.y > screen.visibleFrame.maxY && mouseLocation.y <= screen.frame.maxY
        }
        return false
    }

    /// A Boolean value that indicates whether the mouse pointer is within
    /// the bounds of the current application menu.
    var isMouseInsideApplicationMenu: Bool {
        guard
            let mouseLocation = MouseCursor.location(flipped: true),
            let screen = bestScreen,
            let appState,
            var applicationMenuFrame = appState.menuBarManager.getApplicationMenuFrame(for: screen.displayID)
        else {
            return false
        }
        applicationMenuFrame.size.width += 15 // extra width to accomodate menu padding
        return applicationMenuFrame.contains(mouseLocation)
    }

    /// A Boolean value that indicates whether the mouse pointer is within
    /// the bounds of a menu bar item.
    var isMouseInsideMenuBarItem: Bool {
        guard
            let screen = bestScreen,
            let mouseLocation = MouseCursor.location(flipped: true)
        else {
            return false
        }
        let menuBarItems = MenuBarItem.getMenuBarItemsPrivateAPI(for: screen.displayID, onScreenOnly: true)
        return menuBarItems.contains { $0.frame.contains(mouseLocation) }
    }

    /// A Boolean value that indicates whether the mouse pointer is within
    /// the bounds of an empty space in the menu bar.
    var isMouseInsideEmptyMenuBarSpace: Bool {
        isMouseInsideMenuBar &&
        !isMouseInsideApplicationMenu &&
        !isMouseInsideMenuBarItem
    }

    /// A Boolean value that indicates whether the mouse pointer is within
    /// the bounds of the Ice Bar panel.
    var isMouseInsideIceBar: Bool {
        guard
            let appState,
            let mouseLocation = MouseCursor.location(flipped: false)
        else {
            return false
        }
        let panel = appState.menuBarManager.iceBarPanel
        // pad the frame to be more forgiving if the user accidentally
        // moves their mouse outside of the Ice Bar
        let paddedFrame = panel.frame.insetBy(dx: -10, dy: -10)
        return paddedFrame.contains(mouseLocation)
    }

    /// A Boolean value that indicates whether the mouse pointer is within
    /// the bounds of the Ice icon.
    var isMouseInsideIceIcon: Bool {
        guard
            let appState,
            let visibleSection = appState.menuBarManager.section(withName: .visible),
            let iceIconFrame = visibleSection.controlItem.windowFrame,
            let mouseLocation = MouseCursor.location(flipped: false)
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
