//
//  EventManager.swift
//  Ice
//

import AXSwift
import Cocoa
import Combine

/// Manager for the various event monitors maintained by the app.
@MainActor
final class EventManager {
    /// The shared app state.
    private weak var appState: AppState?

    /// Storage for internal observers.
    private var cancellables = Set<AnyCancellable>()

    /// Cached menu bar window frames per display.
    ///
    /// `isMouseInsideMenuBar` runs on every mouse-move/scroll event, and the
    /// auto-hide/fullscreen branch lists every on-screen window via
    /// `CGWindowListCopyWindowInfo`. The frame only moves on space/display
    /// transitions (observed below to invalidate), so a short-TTL cache keeps
    /// the hot path off WindowServer IPC.
    private var cachedMenuBarFrames = [CGDirectDisplayID: (frame: CGRect, date: Date)]()

    /// Last time a hover/scroll check ran the expensive branch.
    private var lastHoverCheck = Date.distantPast
    private var lastScrollCheck = Date.distantPast

    /// How long a cached menu bar frame is trusted.
    private static let menuBarFrameTTL: TimeInterval = 2

    /// Minimum gap between hover/scroll checks that may hit WindowServer/AX.
    private static let hoverThrottleInterval: TimeInterval = 0.05
    private static let scrollThrottleInterval: TimeInterval = 0.05

    /// Height of the generous top-strip pre-check. The real bar is ~24-33pt;
    /// anything below this can never be inside it, so the check only skips
    /// work it would have done anyway.
    private static let menuBarStripHeight: CGFloat = 40

    // MARK: Monitors

    /// Monitor for mouse down events.
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

    /// Monitor for mouse up events.
    private(set) lazy var mouseUpMonitor = UniversalEventMonitor(
        mask: .leftMouseUp
    ) { [weak self] event in
        self?.handleLeftMouseUp()
        return event
    }

    /// Monitor for mouse dragged events.
    private(set) lazy var mouseDraggedMonitor = UniversalEventMonitor(
        mask: .leftMouseDragged
    ) { [weak self] event in
        self?.handleLeftMouseDragged(with: event)
        return event
    }

    /// Monitor for mouse moved events.
    private(set) lazy var mouseMovedMonitor = UniversalEventMonitor(
        mask: .mouseMoved
    ) { [weak self] event in
        self?.handleShowOnHover()
        return event
    }

    /// Monitor for scroll wheel events.
    private(set) lazy var scrollWheelMonitor = UniversalEventMonitor(
        mask: .scrollWheel
    ) { [weak self] event in
        self?.handleShowOnScroll(with: event)
        return event
    }

    // MARK: All Monitors

    /// All monitors maintained by the app.
    private lazy var allMonitors = [
        mouseDownMonitor,
        mouseUpMonitor,
        mouseDraggedMonitor,
        mouseMovedMonitor,
        scrollWheelMonitor,
    ]

    // MARK: Initializers

    /// Creates an event manager with the given app state.
    init(appState: AppState) {
        self.appState = appState
    }

    /// Sets up the manager.
    func performSetup() {
        startAll()
        configureCancellables()
    }

    /// Configures the internal observers for the manager.
    private func configureCancellables() {
        var c = Set<AnyCancellable>()

        if let appState {
            if let hiddenSection = appState.menuBarManager.section(withName: .hidden) {
                // In fullscreen mode, the menu bar slides down from the top on hover. Observe
                // the frame of the hidden section's control item, which we know will always be
                // in the menu bar, and run the show-on-hover check when it changes.
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

        // The cached menu bar frame only moves on space/display transitions.
        Publishers.Merge(
            NSWorkspace.shared.notificationCenter
                .publisher(for: NSWorkspace.activeSpaceDidChangeNotification)
                .mapToVoid(),
            NotificationCenter.default
                .publisher(for: NSApplication.didChangeScreenParametersNotification)
                .mapToVoid()
        )
        .sink { [weak self] _ in
            self?.cachedMenuBarFrames.removeAll()
        }
        .store(in: &c)

        if let appState {
            // Showing/hiding the system menu bar (or entering/leaving a
            // fullscreen space) slides the menu bar window, so drop the cache.
            appState.menuBarManager.$isMenuBarHiddenBySystem
                .mapToVoid()
                .merge(with: appState.$isActiveSpaceFullscreen.mapToVoid())
                .sink { [weak self] _ in
                    self?.cachedMenuBarFrames.removeAll()
                }
                .store(in: &c)
        }

        cancellables = c
    }

    // MARK: Start/Stop

    /// Starts all monitors.
    func startAll() {
        for monitor in allMonitors {
            monitor.start()
        }
    }

    /// Stops all monitors.
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
            // Short delay helps the toggle action feel more natural.
            try? await Task.sleep(for: .milliseconds(50))

            // Re-verify at fire time: the click may have hit an icon whose AX
            // state lagged at mouse-down, or opened a menu since. Never toggle
            // into an interaction.
            guard !isMenuOpenGlobally(), isMouseInsideEmptyMenuBarSpace else {
                return
            }

            if NSEvent.modifierFlags == .control {
                handleShowRightClickMenu()
            } else if
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

        // Make sure clicking the Ice Bar doesn't trigger rehide.
        guard event.window !== appState.menuBarManager.iceBarPanel else {
            return
        }

        // Only continue if a section is currently visible.
        guard appState.menuBarManager.sections.contains(where: { !$0.isHidden }) else {
            return
        }

        // Make sure the mouse is not in the menu bar.
        guard !isMouseInsideMenuBar else {
            return
        }

        Task {
            let initialSpaceID = Bridging.activeSpaceID

            // Sleep for a bit to give the window under the mouse a chance to focus.
            try? await Task.sleep(for: .seconds(0.25))

            // If clicking caused a space change, don't bother with the window check.
            if Bridging.activeSpaceID != initialSpaceID {
                for section in appState.menuBarManager.sections {
                    section.hide(persistState: false)
                }
                return
            }

            // A tracked menu means the user is mid-interaction (e.g. picking
            // from a dropdown) — never collapse into it. This also spares a
            // window-list fetch while menus are open.
            guard !isMenuOpenGlobally() else {
                return
            }

            // Get the window that the user has clicked into.
            guard let mouseLocation = MouseCursor.locationCoreGraphics else {
                return
            }
            let windowsBelowCursor = WindowInfo.getOnScreenWindows(excludeDesktopWindows: false)
                .filter({ $0.layer < CGWindowLevelForKey(.cursorWindow) })

            // A dropdown/panel hanging from the menu bar: interacting with it
            // must not collapse the sections — only its closing (a click
            // elsewhere) may. Checked before the title filter because panels
            // often have no window title. Regular apps can own status items too.
            if let topmost = windowsBelowCursor.first(where: { $0.frame.contains(mouseLocation) }),
               isMenuBarDropdownWindow(topmost) {
                return
            }

            guard
                let windowUnderMouse = windowsBelowCursor
                    .first(where: { $0.frame.contains(mouseLocation) && $0.title?.isEmpty == false }),
                let owningApplication = windowUnderMouse.owningApplication
            else {
                return
            }

            // The dock is an exception to the following check.
            if owningApplication.bundleIdentifier != "com.apple.dock" {
                // Only continue if the user has clicked into an active window with
                // a regular activation policy.
                guard
                    owningApplication.isActive,
                    owningApplication.activationPolicy == .regular
                else {
                    return
                }
            }

            // If all the above checks have passed, hide all sections.
            for section in appState.menuBarManager.sections {
                section.hide(persistState: false)
            }
        }
    }

    // MARK: Handle Show Right Click Menu

    private func handleShowRightClickMenu() {
        guard
            let appState,
            appState.settingsManager.advancedSettingsManager.showContextMenuOnRightClick,
            isMouseInsideEmptyMenuBarSpace,
            let mouseLocation = MouseCursor.locationAppKit
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
                    // We have a left click that is inside the menu bar while at least one
                    // section is visible or the mouse is inside the Ice icon.
                    appState.preventShowOnHover()
                }
            case .rightMouseDown:
                if appState.menuBarManager.sections.contains(where: { !$0.isHidden }) {
                    // We have a right click that is inside the menu bar while at least one
                    // section is visible.
                    appState.preventShowOnHover()
                }
            default:
                break
            }
        } else if !isMouseInsideApplicationMenu {
            // We have a left or right click that is inside the menu bar, outside
            // a menu bar item, and outside the application menu, so it _must_ be
            // inside an empty menu bar space.
            appState.preventShowOnHover()
        }
    }

    // MARK: Handle Left Mouse Up

    private func handleLeftMouseUp() {
        guard let appearanceManager = appState?.appearanceManager else {
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

        // Notify each overlay panel that a menu bar item is being dragged.
        appState.appearanceManager.setIsDraggingMenuBarItem(true)

        // Don't continue if the setting to show the sections is disabled, or
        // while the Layout pane is editing: everything is already shown, and
        // drawing collapsed dividers mid-drag would shift the icons under it.
        guard
            appState.settingsManager.advancedSettingsManager.showAllSectionsOnUserDrag,
            !appState.menuBarManager.isLayoutEditing
        else {
            return
        }

        // Show all items, including section dividers. A drag reveal is
        // temporary, so it must not overwrite the saved show/hide choice.
        // Already-shown sections are left alone so their state revision only
        // moves on a real change (layout editing relies on it).
        for section in appState.menuBarManager.sections {
            if section.controlItem.state != .showItems {
                section.setState(.showItems, persist: false)
            }
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

        // Make sure the "ShowOnHover" feature is enabled and not prevented.
        guard
            appState.settingsManager.generalSettingsManager.showOnHover,
            !appState.isShowOnHoverPrevented
        else {
            return
        }

        // Only continue if we have a hidden section (we should).
        guard let hiddenSection = appState.menuBarManager.section(withName: .hidden) else {
            return
        }

        // ponytail: mouseMoved fires at 10s-100s/sec and the check below hits
        // WindowServer/AX. Coalesce to ~20/s; well under showOnHoverDelay (0.2s).
        guard Date().timeIntervalSince(lastHoverCheck) >= Self.hoverThrottleInterval else {
            return
        }
        lastHoverCheck = Date()

        let delay = appState.settingsManager.advancedSettingsManager.showOnHoverDelay

        Task {
            if hiddenSection.isHidden {
                guard self.isMouseInsideEmptyMenuBarSpace else {
                    return
                }
                try? await Task.sleep(for: .seconds(delay))
                // Make sure the mouse is still inside.
                guard self.isMouseInsideEmptyMenuBarSpace else {
                    return
                }
                hiddenSection.show(persistState: false)
            } else {
                guard
                    !self.isMouseInsideMenuBar,
                    !self.isMouseInsideIceBar
                else {
                    return
                }
                try? await Task.sleep(for: .seconds(delay))
                // Make sure the mouse is still outside.
                guard
                    !self.isMouseInsideMenuBar,
                    !self.isMouseInsideIceBar
                else {
                    return
                }
                hiddenSection.hide(persistState: false)
            }
        }
    }

    // MARK: Handle Show On Scroll

    private func handleShowOnScroll(with event: NSEvent) {
        guard let appState else {
            return
        }

        // Make sure the "ShowOnScroll" feature is enabled.
        guard appState.settingsManager.generalSettingsManager.showOnScroll else {
            return
        }

        // ponytail: scroll momentum bursts; same coalescing as hover.
        guard Date().timeIntervalSince(lastScrollCheck) >= Self.scrollThrottleInterval else {
            return
        }
        lastScrollCheck = Date()

        // Make sure the mouse is inside the menu bar.
        guard isMouseInsideMenuBar else {
            return
        }

        // Only continue if we have a hidden section (we should).
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
            guard let mouseLocation = MouseCursor.locationCoreGraphics else {
                return false
            }
            // ponytail: cheap reject before CGWindowListCopyWindowInfo. The bar
            // is a thin strip at the display's top edge; ~all mouse-move events
            // are below it and would miss the contains() check anyway.
            let displayBounds = CGDisplayBounds(screen.displayID)
            guard
                displayBounds.contains(mouseLocation),
                mouseLocation.y <= displayBounds.origin.y + Self.menuBarStripHeight
            else {
                return false
            }
            let displayID = screen.displayID
            if
                let cached = cachedMenuBarFrames[displayID],
                Date().timeIntervalSince(cached.date) < Self.menuBarFrameTTL
            {
                return cached.frame.contains(mouseLocation)
            }
            guard let menuBarWindow = WindowInfo.getMenuBarWindow(for: displayID) else {
                return false
            }
            cachedMenuBarFrames[displayID] = (menuBarWindow.frame, Date())
            return menuBarWindow.frame.contains(mouseLocation)
        } else if let mouseLocation = MouseCursor.locationAppKit {
            return mouseLocation.y > screen.visibleFrame.maxY && mouseLocation.y <= screen.frame.maxY
        }
        return false
    }

    /// A Boolean value that indicates whether the mouse pointer is within
    /// the bounds of the current application menu.
    var isMouseInsideApplicationMenu: Bool {
        guard
            let mouseLocation = MouseCursor.locationCoreGraphics,
            let screen = bestScreen,
            let appState,
            var applicationMenuFrame = appState.menuBarManager.getApplicationMenuFrame(for: screen.displayID)
        else {
            return false
        }
        applicationMenuFrame.size.width += applicationMenuFrame.origin.x - screen.frame.origin.x
        applicationMenuFrame.origin.x = screen.frame.origin.x
        return applicationMenuFrame.contains(mouseLocation)
    }

    /// A Boolean value that indicates whether the mouse pointer is within
    /// the bounds of a menu bar item.
    var isMouseInsideMenuBarItem: Bool {
        guard
            let screen = bestScreen,
            let mouseLocation = MouseCursor.locationCoreGraphics
        else {
            return false
        }
        if isMouseInsideOwnControlItem {
            return true
        }
        let menuBarItems = MenuBarItem.getMenuBarItems(on: screen.displayID, onScreenOnly: true, activeSpaceOnly: true)
        if menuBarItems.contains(where: { $0.frame.contains(mouseLocation) }) {
            return true
        }
        // On macOS 27 the window server vends no per-item windows, so the
        // lookup above is always empty and clicks on third-party icons look
        // like clicks on empty space — collapsing the sections mid-interaction
        // (e.g. just as the icon's dropdown opens). Fall back to a single AX
        // hit test, using the same trailing-cluster roles as the overlay.
        if let appState, appState.itemManager.isItemDiscoveryUnavailable {
            return isMouseInsideAXMenuBarItem(at: mouseLocation)
        }
        return false
    }

    /// AX hit test for a menu bar item at the given CoreGraphics point.
    ///
    /// `AXGroup` covers the MenuBarAgent/ControlCenter cluster;
    /// `AXMenuBarItem`/`AXButton`/`AXImage` cover third-party extras, excluding
    /// the frontmost app's own menus. An open menu over the bar (`AXMenu` /
    /// `AXMenuItem`) also counts: the user is interacting with it, so the spot
    /// is not empty space. A bare `AXMenuBar` reads as empty unless it belongs
    /// to another app's icon on a secondary display (see
    /// ``isOtherAppsMenuBar(_:at:)``). Anything without AX permission, or any
    /// other role (wallpaper, …), reads as empty.
    private func isMouseInsideAXMenuBarItem(at point: CGPoint) -> Bool {
        guard
            let element = try? systemWideElement.elementAtPosition(Float(point.x), Float(point.y)),
            let role: String = try? element.attribute("AXRole")
        else {
            return false
        }
        switch role {
        case "AXGroup", "AXMenu", "AXMenuItem":
            return true
        case "AXMenuBarItem", "AXButton", "AXImage":
            guard let pid: pid_t = try? element.pid() else {
                // A status-looking element we can't attribute is more likely
                // an icon than empty space, and a missed toggle beats a
                // mid-interaction collapse.
                return true
            }
            if pid == ProcessInfo.processInfo.processIdentifier {
                // On a wide screen part of Ice's hiding spacer stays on
                // screen as a blank strip; clicks there are empty space.
                let identifier: String? = try? element.attribute("AXIdentifier")
                let frame: CGRect? = try? element.attribute("AXFrame")
                if identifier?.hasPrefix(ControlItem.spacerExtensionIdentifier) == true || (frame?.width ?? 0) > 200 {
                    return false
                }
            }
            return pid != NSWorkspace.shared.frontmostApplication?.processIdentifier
        case "AXMenuBar":
            return isOtherAppsMenuBar(element, at: point)
        default:
            return false
        }
    }

    /// Whether a bare `AXMenuBar` hit is really another app's status icon.
    ///
    /// On a display other than the primary one, a third-party icon reports
    /// its app's whole menu bar instead of an item: apps only know where their
    /// items sit on the primary display. Empty space there reports the menu
    /// bar of the app whose menus that display shows, so a menu bar from any
    /// other app is an icon. Ice's own is its blank spacer: empty space.
    private func isOtherAppsMenuBar(_ element: UIElement, at point: CGPoint) -> Bool {
        guard
            let appState,
            let pid: pid_t = try? element.pid(),
            pid != ProcessInfo.processInfo.processIdentifier,
            let screen = NSScreen.screens.first(where: { CGDisplayBounds($0.displayID).contains(point) }),
            let owner = appState.menuBarManager.menuBarElement(for: screen.displayID),
            let ownerPID: pid_t = try? owner.pid()
        else {
            return false
        }
        return pid != ownerPID
    }

    /// A Boolean value that indicates whether the mouse pointer is within
    /// the bounds of one of Ice's own section control items.
    ///
    /// On macOS 27 the window server no longer vends per-item windows, so the
    /// lookup above is always empty and every click looks like a click on empty
    /// menu bar space — including clicks on Ice's own controls, which then
    /// toggle twice (once from the control itself, once from the delayed
    /// empty-space handler) and land wherever the timing race leaves them.
    /// Ice's own control windows always exist, so check those directly. The Ice
    /// icon always counts; section dividers only count when actually drawn as
    /// chevrons (shown with dividers enabled) — an expanded hiding spacer is
    /// blank space and must stay clickable-as-empty.
    private var isMouseInsideOwnControlItem: Bool {
        guard
            let appState,
            let mouseLocation = MouseCursor.locationAppKit
        else {
            return false
        }
        return appState.menuBarManager.sections.contains { section in
            let controlItem = section.controlItem
            if controlItem.isSectionDivider {
                guard controlItem.state == .showItems, controlItem.isVisible else {
                    return false
                }
            }
            guard let window = controlItem.window else {
                return false
            }
            return window.frame.contains(mouseLocation)
        }
    }

    /// A Boolean value that indicates whether the mouse pointer is within
    /// the bounds of the screen's notch, if it has one.
    ///
    /// If the screen returned from ``bestScreen`` does not have a notch,
    /// this property returns `false`.
    var isMouseInsideNotch: Bool {
        guard
            let screen = bestScreen,
            let mouseLocation = MouseCursor.locationAppKit,
            let frameOfNotch = screen.frameOfNotch
        else {
            return false
        }
        return frameOfNotch.contains(mouseLocation)
    }

    /// A Boolean value that indicates whether the mouse pointer is within
    /// the bounds of an empty space in the menu bar.
    var isMouseInsideEmptyMenuBarSpace: Bool {
        isMouseInsideMenuBar &&
        !isMouseInsideApplicationMenu &&
        !isMouseInsideMenuBarItem &&
        !isMouseInsideNotch
    }

    /// A Boolean value that indicates whether the mouse pointer is within
    /// the bounds of the Ice Bar panel.
    var isMouseInsideIceBar: Bool {
        guard
            let appState,
            let mouseLocation = MouseCursor.locationAppKit
        else {
            return false
        }
        let panel = appState.menuBarManager.iceBarPanel
        // Pad the frame to be more forgiving if the user accidentally
        // moves their mouse outside of the Ice Bar.
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
            let mouseLocation = MouseCursor.locationAppKit
        else {
            return false
        }
        return iceIconFrame.contains(mouseLocation)
    }

    /// Whether the user is currently interacting with an open menu, globally.
    ///
    /// Standard menus take keyboard focus while tracking, so a focused menu
    /// element (or one nested inside a menu/popover) means a dropdown is open
    /// somewhere — even below the menu bar, where geometry checks can't see
    /// it. Non-activating custom panels don't move focus and are covered by
    /// the window-geometry spare instead. Without AX permission this reads
    /// false, preserving the old behavior.
    private func isMenuOpenGlobally() -> Bool {
        let focused: UIElement? = (try? systemWideElement.attribute("AXFocusedUIElement")) ?? nil
        var current = focused
        var depth = 0
        while let element = current, depth < 6 {
            if let role: String = try? element.attribute("AXRole"),
               role == "AXMenu" || role == "AXMenuItem" || role == "AXPopover" {
                return true
            }
            current = (try? element.attribute("AXParent")) ?? nil
            depth += 1
        }
        return false
    }

    /// Whether the given window looks like a dropdown/panel hanging from the
    /// menu bar: a smallish window near the bar's bottom edge.
    ///
    /// Standard menus hang just below the bar; custom panels may start a bit
    /// lower. Anything clearly larger or lower is treated as a regular window.
    /// A false spare only keeps the sections open until the next outside
    /// click, while a false hide collapses them mid-interaction.
    private func isMenuBarDropdownWindow(_ window: WindowInfo) -> Bool {
        guard let screen = bestScreen else {
            return false
        }
        let bounds = CGDisplayBounds(screen.displayID)
        let barHeight = screen.frame.maxY - screen.visibleFrame.maxY
        let barBottom = bounds.minY + barHeight
        let frame = window.frame
        return frame.minY <= barBottom + 120 && frame.height <= 500 && frame.width <= 700
    }
}

// MARK: - Logger
private extension Logger {
    static let eventManager = Logger(category: "EventManager")
}
