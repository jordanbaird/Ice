//
//  HIDEventManager.swift
//  Ice
//

import Cocoa
import Combine
import OSLog

/// Manager that monitors input events and implements the features
/// that are triggered by them, such as showing hidden items on
/// click/hover/scroll.
@MainActor
final class HIDEventManager: ObservableObject {
    /// A Boolean value that indicates whether the user is dragging
    /// a menu bar item.
    @Published private(set) var isDraggingMenuBarItem = false

    /// The shared app state.
    private weak var appState: AppState?

    /// Storage for internal observers.
    private var cancellables = Set<AnyCancellable>()

    /// History of the manager's enabled states.
    private var enabledStateStack = [Bool]()

    /// The last empty menu bar spot hovered on each display (see `ItemClicker27`).
    private var lastEmptyMenuBarPoints = [CGDirectDisplayID: CGPoint]()

    /// Until when the release of a held-back click is held back as well (see
    /// `handleSystemItemClick27`). The deadline keeps a release that never comes from
    /// swallowing an unrelated one later.
    private var heldBackReleaseUntil: ContinuousClock.Instant?

    /// The application menu frame last read through Accessibility, with the display and
    /// the menu bar's owner it was read for (see `applicationMenuFrame(for:)`).
    private var applicationMenuFrameCache: (
        displayID: CGDirectDisplayID,
        ownerPID: pid_t?,
        frame: CGRect?,
        readAt: ContinuousClock.Instant
    )?

    /// The bounds of the menu bar item windows last read before macOS 27
    /// (see `menuBarItemBounds()`).
    private var menuBarItemBoundsCache: (bounds: [CGRect], readAt: ContinuousClock.Instant)?

    /// What a pending show-on-hover task is going to do.
    private enum HoverAction: Equatable {
        case show(CGDirectDisplayID)
        case hide
    }

    /// The pending show-on-hover task, with what it is going to do.
    private var hoverTask: (action: HoverAction, task: Task<Void, Never>)?


    /// A Boolean value that indicates whether the manager is enabled.
    private var isEnabled = false {
        didSet {
            if isEnabled {
                for monitor in allMonitors {
                    monitor.start()
                }
            } else {
                for monitor in allMonitors {
                    monitor.stop()
                }
            }
            updateMouseMovedTap()
        }
    }

    // MARK: Monitors

    /// Monitor for mouse down events.
    private(set) lazy var mouseDownMonitor = EventMonitor.universal(
        for: [.leftMouseDown, .rightMouseDown]
    ) { [weak self] event in
        guard let self, isEnabled, let appState, let screen = bestScreen(appState: appState) else {
            return event
        }
        // Ice's own click that makes a display's menu bar active (see `ItemClicker27`).
        if event.cgEvent?.getIntegerValueField(.eventSourceUserData) == HIDEventManager.menuBarActivationMarker {
            return event
        }
        switch event.type {
        case .leftMouseDown:
            handleShowOnClick(appState: appState, screen: screen)
            handleSmartRehide(with: event, appState: appState, screen: screen)
        case .rightMouseDown:
            handleSecondaryContextMenu(appState: appState, screen: screen)
        default:
            return event
        }
        handlePreventShowOnHover(with: event, appState: appState, screen: screen)
        return event
    }

    /// Monitor for mouse up events.
    private(set) lazy var mouseUpMonitor = EventMonitor.universal(
        for: .leftMouseUp
    ) { [weak self] event in
        guard let self, isEnabled else {
            return event
        }
        handleMenuBarItemDragStop()
        return event
    }

    /// Monitor for mouse dragged events.
    private(set) lazy var mouseDraggedMonitor = EventMonitor.universal(
        for: .leftMouseDragged
    ) { [weak self] event in
        if let self, isEnabled, let appState, let screen = bestScreen(appState: appState) {
            handleMenuBarItemDragStart(with: event, appState: appState, screen: screen)
        }
        return event
    }

    /// Tap for mouse moved events.
    private(set) lazy var mouseMovedTap = EventTap(
        type: .mouseMoved,
        location: .hidEventTap,
        placement: .tailAppendEventTap,
        option: .listenOnly
    ) { [weak self] _, event in
        if
            let self,
            isEnabled,
            let appState,
            appState.settings.general.showOnHover,
            let screen = bestScreen(appState: appState)
        {
            handleShowOnHover(appState: appState, screen: screen, location: MouseHelpers.Location(event: event))
        }
        return event
    }

    /// Monitor for scroll wheel events.
    private(set) lazy var scrollWheelMonitor = EventMonitor.universal(
        for: .scrollWheel
    ) { [weak self] event in
        if let self, isEnabled, let appState, let screen = bestScreen(appState: appState) {
            handleShowOnScroll(with: event, appState: appState, screen: screen)
        }
        return event
    }

    /// Tap that lets clicks reach the system items while items are concealed on macOS 27.
    ///
    /// While an assessment-mode assertion is live, MenuBarAgent ignores clicks on the
    /// clock (measured on macOS 27.0). The tap holds such a click back, releases the
    /// assertions for a moment, and replays the click.
    private(set) lazy var systemItemClickTap = EventTap(
        types: [.leftMouseDown, .leftMouseUp],
        location: .hidEventTap,
        placement: .headInsertEventTap,
        option: .defaultTap
    ) { [weak self] _, event in
        guard let self, isEnabled, let appState else {
            return event
        }
        if #available(macOS 27.0, *) {
            return handleSystemItemClick27(event, appState: appState)
        }
        return event
    }

    // MARK: All Monitors

    /// All monitors maintained by the manager, except ``mouseMovedTap``,
    /// which only runs while show-on-hover is on (see `updateMouseMovedTap(showOnHover:)`).
    private lazy var allMonitors: [any EventMonitorProtocol] = {
        var monitors: [any EventMonitorProtocol] = [
            mouseDownMonitor,
            mouseUpMonitor,
            mouseDraggedMonitor,
            scrollWheelMonitor,
        ]
        if #available(macOS 27.0, *) {
            monitors.append(systemItemClickTap)
        }
        return monitors
    }()

    // MARK: Setup

    /// Sets up the manager.
    func performSetup(with appState: AppState) {
        self.appState = appState
        startAll()
        configureCancellables()
    }

    /// Configures the internal observers for the manager.
    private func configureCancellables() {
        var c = Set<AnyCancellable>()

        appState?.settings.general.$showOnHover
            .removeDuplicates()
            .sink { [weak self] showOnHover in
                self?.updateMouseMovedTap(showOnHover: showOnHover)
            }
            .store(in: &c)

        if let appState, let hiddenSection = appState.menuBarManager.section(withName: .hidden) {
            // In fullscreen mode, the menu bar slides down from the top on hover. Observe the
            // frame of the hidden section's control item, which we know will always be in the
            // menu bar, and run the show-on-hover check when it changes.
            Publishers.CombineLatest3(
                hiddenSection.controlItem.$frame,
                appState.$activeSpace.map(\.isFullscreen),
                appState.menuBarManager.$isMenuBarHiddenBySystem
            )
            .receive(on: DispatchQueue.main)
            .sink { [weak self, weak appState] _, isFullscreen, isMenuBarHiddenBySystem in
                guard let self, isEnabled, let appState, isFullscreen || isMenuBarHiddenBySystem else {
                    return
                }
                if let screen = bestScreen(appState: appState) {
                    handleShowOnHover(appState: appState, screen: screen, location: MouseHelpers.location)
                }
            }
            .store(in: &c)

            // The application menu belongs to the frontmost app, and differs between spaces,
            // as do the item windows.
            appState.$activeSpace
                .sink { [weak self] _ in
                    self?.applicationMenuFrameCache = nil
                    self?.menuBarItemBoundsCache = nil
                }
                .store(in: &c)
        }

        NSWorkspace.shared.notificationCenter
            .publisher(for: NSWorkspace.didActivateApplicationNotification)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                MainActor.assumeIsolated {
                    self?.applicationMenuFrameCache = nil
                }
            }
            .store(in: &c)

        cancellables = c
    }

    // MARK: Start/Stop

    /// Enables the mouse moved tap while the manager is enabled and show-on-hover
    /// is on, and disables it otherwise.
    ///
    /// Every mouse move in the system goes through the tap, so it is not left
    /// running for a feature that is off.
    private func updateMouseMovedTap(showOnHover: Bool? = nil) {
        if isEnabled, showOnHover ?? appState?.settings.general.showOnHover ?? false {
            mouseMovedTap.enable()
        } else {
            mouseMovedTap.disable()
        }
    }

    /// Starts all monitors.
    func startAll() {
        isEnabled = enabledStateStack.popLast() ?? true
    }

    /// Stops all monitors.
    func stopAll() {
        enabledStateStack.append(isEnabled)
        isEnabled = false
    }
}

// MARK: - Handler Methods

extension HIDEventManager {

    // MARK: Handle Show On Click

    private func handleShowOnClick(appState: AppState, screen: NSScreen) {
        guard
            appState.settings.general.showOnClick,
            isMouseInsideEmptyMenuBarSpace(appState: appState, screen: screen)
        else {
            return
        }
        let clickLocation = MouseHelpers.location?.coreGraphics

        Task {
            if await isMenuBarItem(at: clickLocation) {
                return
            }
            if NSEvent.modifierFlags == .control {
                handleSecondaryContextMenu(appState: appState, screen: screen)
                return
            }

            let targetSection: MenuBarSection

            if
                NSEvent.modifierFlags == .option,
                let alwaysHiddenSection = appState.menuBarManager.section(withName: .alwaysHidden),
                alwaysHiddenSection.isEnabled
            {
                targetSection = alwaysHiddenSection
            } else if
                let hiddenSection = appState.menuBarManager.section(withName: .hidden),
                hiddenSection.isEnabled
            {
                targetSection = hiddenSection
            } else {
                return
            }

            targetSection.toggle()
        }
    }

    /// Whether a click at the given location, which Ice's cached frames took for empty bar,
    /// actually landed on a menu bar item. Only macOS 27 needs asking: there are no item
    /// windows there, and the cached frames miss items (see `MenuBarItemProvider27.hasItem`).
    private func isMenuBarItem(at location: CGPoint?) async -> Bool {
        guard #available(macOS 27.0, *), let location else {
            return false
        }
        return await MenuBarItemProvider27.hasItem(at: location)
    }

    // MARK: Handle Smart Rehide

    private func handleSmartRehide(with event: NSEvent, appState: AppState, screen: NSScreen) {
        guard
            appState.settings.general.autoRehide,
            case .smart = appState.settings.general.rehideStrategy
        else {
            return
        }

        // Make sure clicking the Ice icon doesn't trigger rehide.
        if let iceIcon = appState.menuBarManager.controlItem(withName: .visible) {
            guard event.window !== iceIcon.window else {
                return
            }
        }

        // Only continue if the click is not inside the Ice Bar, at
        // least one section is visible, and the mouse is not inside
        // the menu bar.
        guard
            event.window !== appState.menuBarManager.iceBarPanel,
            appState.menuBarManager.hasVisibleSection,
            !isMouseInsideMenuBar(appState: appState, screen: screen)
        else {
            return
        }

        let initialSpaceID = Bridging.getActiveSpaceID()

        Task {
            // Give the window under the mouse a chance to focus.
            try await Task.sleep(for: .milliseconds(250))

            // Don't bother checking the window if the click caused
            // a space change.
            if Bridging.getActiveSpaceID() != initialSpaceID {
                for section in appState.menuBarManager.sections {
                    section.hide()
                }
                return
            }

            // Get the window that was clicked.
            guard
                let mouseLocation = MouseHelpers.locationCoreGraphics,
                let windowUnderMouse = WindowInfo.createWindows(option: .onScreen)
                    .filter({ $0.layer < CGWindowLevelForKey(.cursorWindow) })
                    .first(where: { $0.bounds.contains(mouseLocation) && $0.title?.isEmpty == false }),
                let owningApplication = windowUnderMouse.owningApplication
            else {
                return
            }

            // Note: The Dock is an exception to the following check.
            if owningApplication.bundleIdentifier != "com.apple.dock" {
                // Only continue if the clicked app is active, and has
                // a regular activation policy.
                guard
                    owningApplication.isActive,
                    owningApplication.activationPolicy == .regular
                else {
                    return
                }
            }

            // All checks have passed, hide the sections.
            for section in appState.menuBarManager.sections {
                section.hide()
            }
        }
    }

    // MARK: Handle Secondary Context Menu

    private func handleSecondaryContextMenu(appState: AppState, screen: NSScreen) {
        Task {
            guard
                appState.settings.advanced.enableSecondaryContextMenu,
                isMouseInsideEmptyMenuBarSpace(appState: appState, screen: screen),
                let mouseLocation = MouseHelpers.locationAppKit,
                await !isMenuBarItem(at: MouseHelpers.location?.coreGraphics)
            else {
                return
            }
            // Delay prevents the menu from immediately closing.
            try await Task.sleep(for: .milliseconds(100))
            appState.menuBarManager.showSecondaryContextMenu(at: mouseLocation)
        }
    }

    // MARK: Handle Menu Bar Item Drag Stop

    private func handleMenuBarItemDragStop() {
        if isDraggingMenuBarItem {
            isDraggingMenuBarItem = false
        }
    }

    // MARK: Handle Menu Bar Item Drag Start

    private func handleMenuBarItemDragStart(with event: NSEvent, appState: AppState, screen: NSScreen) {
        guard
            !isDraggingMenuBarItem,
            event.modifierFlags.contains(.command),
            isMouseInsideMenuBar(appState: appState, screen: screen)
        else {
            return
        }

        isDraggingMenuBarItem = true

        if appState.settings.advanced.showAllSectionsOnUserDrag {
            for section in appState.menuBarManager.sections {
                section.controlItem.state = .showSection
            }
        }
    }

    // MARK: Handle System Item Clicks (macOS 27)

    /// Marks the clicks Ice replays, so the tap lets them through.
    private static let replayedClickMarker: Int64 = 0x1CE_27_C1C

    /// Times the steps of a bridged click, which happen on both opening and closing a panel.
    private static let bridgeLogger = Logger(subsystem: "com.jordanbaird.Ice", category: "ClickBridge27")

    /// Marks Ice's click that makes a display's menu bar active before an item is pressed.
    static let menuBarActivationMarker: Int64 = 0x1CE_27_BA2

    /// The last empty menu bar spot hovered on the given display.
    func lastEmptyMenuBarPoint(for displayID: CGDirectDisplayID) -> CGPoint? {
        lastEmptyMenuBarPoints[displayID]
    }

    /// System items that do not open from an Accessibility press, so a click on them has to
    /// go through MenuBarAgent. Seeded with what was measured on macOS 27.0; anything else
    /// that turns out to ignore the press joins them at its first click.
    private nonisolated(unsafe) static var systemItemsIgnoringPress: Set<String> = [
        "com.apple.menuextra.clock",
        "com.apple.menuextra.battery",
        "com.apple.menuextra.wifi",
    ]

    /// The system item whose panel Ice last opened, so a second click on the same item is
    /// understood as the click that dismisses it.
    private nonisolated(unsafe) static var itemShowingPanel: String?

    @available(macOS 27.0, *)
    private func handleSystemItemClick27(_ event: CGEvent, appState: AppState) -> CGEvent? {
        guard event.getIntegerValueField(.eventSourceUserData) != Self.replayedClickMarker else {
            return event
        }
        if event.type == .leftMouseUp {
            // A press Ice holds back has its release held back with it. MenuBarAgent would
            // otherwise be handed a release with no press behind it, moments before the
            // replayed click that carries both.
            guard let until = heldBackReleaseUntil, ContinuousClock.now < until else {
                heldBackReleaseUntil = nil
                return event
            }
            heldBackReleaseUntil = nil
            return nil
        }
        let concealer = appState.concealer27
        // Every click in the system waits on this tap, so one that cannot need bridging is
        // let through before any work is done (`ClockBridgeZone27` says the same, later).
        guard concealer.isConcealing else {
            return event
        }
        // The frames of the display the click landed on, so the clock of the display whose bar
        // is not active is recognised as well.
        let clickedDisplay = NSScreen.screens.first { CGDisplayBounds($0.displayID).contains(event.location) }?.displayID
        let framesOnDisplay = clickedDisplay.map { MenuBarItemProvider27.systemItemFrames(for: $0) } ?? []
        guard ClockBridgeZone27.shouldBridge(
            click: event.location,
            systemItemFrames: framesOnDisplay.isEmpty ? MenuBarItemProvider27.systemItemFrames() : framesOnDisplay,
            isConcealing: concealer.isConcealing
        ) else {
            return event
        }
        let location = event.location
        // Control Centre opens from an Accessibility press even while items are concealed
        // (measured on macOS 27.0: its panel appears after about 177 ms). The clock, the
        // battery and Wi-Fi ignore the press, so for those the concealment is lifted and the
        // click replayed — and put back the moment their panel is up, rather than after a
        // fixed second and a half, which is what made every hidden item flash into view.
        let systemItem = MenuBarItemProvider27.systemItem(at: location)
        let mayOpenFromPress = systemItem.map { !Self.systemItemsIgnoringPress.contains($0.identifier) } ?? false
        Task {
            // A click that lands while a panel is up is the click that dismisses it, and
            // Escape dismisses it just as well — with no lift of concealment at all. Lifting
            // for such a click brought every hidden item back on screen first, and the panel
            // only answered once MenuBarAgent had finished moving the bar: the icons appeared,
            // and the panel closed late behind them.
            if ItemClick27.openPanelWindow(windows: Self.windowsForPanelCheck()) != nil {
                Self.postEscape()
                Self.bridgeLogger.debug("Click bridge: a panel was open, dismissed with Escape")
                guard systemItem?.identifier != Self.itemShowingPanel else {
                    Self.itemShowingPanel = nil
                    return
                }
                // A different system item was clicked, so its own panel still has to open.
                try? await Task.sleep(for: Self.panelDismissWait)
            }
            if mayOpenFromPress, let systemItem {
                let baseline = Self.windowNumbers()
                await Self.press(systemItem.element)
                if await Self.waitForPanel(baseline: baseline, pollsOf50ms: 5) {
                    // Remembered here as well, or the next click on this item would dismiss
                    // its panel and open it again in the same breath.
                    Self.itemShowingPanel = systemItem.identifier
                    return
                }
                // Waiting for a panel that never comes only delays the click, so an item
                // that ignored the press is not asked again while Ice runs.
                Self.systemItemsIgnoringPress.insert(systemItem.identifier)
            }
            // The click is replayed the moment the assertion is really gone rather than on a
            // timer: releasing it queues behind other concealment work, and MenuBarAgent ignores
            // a click that arrives while the assertion still stands, which is why the clock
            // sometimes did nothing and opened on the second try. Nothing else is done before
            // the replay, so the click is as quick as the release allows.
            let bridgeStarted = ProcessInfo.processInfo.systemUptime
            Self.bridgeLogger.debug("Click bridge: holding the click, lifting concealment")
            await concealer.suspendReleased(for: Self.clickRestoreDelay)
            let released = (ProcessInfo.processInfo.systemUptime - bridgeStarted) * 1000
            Self.replayClick(at: location)
            Self.itemShowingPanel = systemItem?.identifier
            Self.bridgeLogger.debug("Click bridge: lifted in \(released, privacy: .public) ms, click replayed")
        }
        heldBackReleaseUntil = .now + .seconds(1)
        return nil
    }

    /// How long concealment stays lifted around a replayed click.
    ///
    /// MenuBarAgent needs the lift to act on the click at all, and every millisecond of it is
    /// a millisecond of the bar moving: the items slide back in, then out again. The panel's
    /// own window appears about 166 ms after the click (measured on macOS 27.0), so a lift
    /// that ends around then has the bar settling while the panel animates, which is what made
    /// the animation stutter.
    ///
    /// Measured on macOS 27.0 with `Scripts/macos27/clock-restore.swift`, on both displays: a
    /// lift of 40 ms loses the click 6 times in 16, 60 ms once in 16, and 80, 100 and 120 ms
    /// each opened the panel 16 times in 16. So the floor is around 60 ms, and 120 ms keeps
    /// double that margin while still ending before the panel appears. The
    /// `MacOS27ClickRestoreDelay` default overrides it, in milliseconds, for measuring.
    private static var clickRestoreDelay: Duration {
        let stored = Defaults.integer(forKey: .macOS27ClickRestoreDelay)
        return .milliseconds(stored > 0 ? min(max(stored, 30), 2000) : 120)
    }



    /// The window numbers currently on screen.
    private static func windowNumbers() -> Set<Int> {
        let windows = CGWindowListCopyWindowInfo([.optionOnScreenOnly], kCGNullWindowID) as? [[String: Any]] ?? []
        return Set(windows.compactMap { $0[kCGWindowNumber as String] as? Int })
    }

    /// The processes that draw the system items' panels.
    ///
    /// Without this, the Dock passes for an open panel: its window stands at layer 20 and the
    /// full size of the display, and it is always there, so every click looked like a click
    /// that closes a panel and every wait for that panel to go ran into its timeout (measured
    /// on macOS 27.0: 12 clicks in a row judged "panel already open").
    private static let panelOwnerBundleIDs: Set<String> = [
        "com.apple.notificationcenterui",
        "com.apple.controlcenter",
    ]

    /// The process identifiers of ``panelOwnerBundleIDs``, from the last time all of them
    /// were running.
    private static var panelOwnerPIDsCache: Set<pid_t>?

    /// The process identifiers of the processes that draw the system items' panels.
    ///
    /// Asking for every running application is not cheap, and the panel check is polled, so
    /// the identifiers are kept for as long as each of those processes is still alive.
    private static var panelOwnerPIDs: Set<pid_t> {
        if
            let panelOwnerPIDsCache,
            panelOwnerPIDsCache.count == panelOwnerBundleIDs.count,
            panelOwnerPIDsCache.allSatisfy({ kill($0, 0) == 0 })
        {
            return panelOwnerPIDsCache
        }
        let pids = Set(
            NSWorkspace.shared.runningApplications
                .filter { panelOwnerBundleIDs.contains($0.bundleIdentifier ?? "") }
                .map(\.processIdentifier)
        )
        panelOwnerPIDsCache = pids
        return pids
    }

    /// The windows on screen that could be a system item's panel, as `ItemClick27` wants them.
    private static func windowsForPanelCheck() -> [(number: Int, layer: Int, height: CGFloat)] {
        let owners = panelOwnerPIDs
        let windows = CGWindowListCopyWindowInfo([.optionOnScreenOnly], kCGNullWindowID) as? [[String: Any]] ?? []
        return windows.compactMap { window in
            guard
                let number = window[kCGWindowNumber as String] as? Int,
                let layer = window[kCGWindowLayer as String] as? Int,
                let ownerPID = window[kCGWindowOwnerPID as String] as? pid_t,
                owners.contains(ownerPID),
                let bounds = window[kCGWindowBounds as String] as? [String: CGFloat],
                let height = bounds["Height"]
            else {
                return nil
            }
            return (number: number, layer: layer, height: height)
        }
    }

    /// How long the panel that was open takes to go after Escape, before the item that was
    /// clicked is given its own turn.
    private static let panelDismissWait = Duration.milliseconds(120)

    /// Presses Escape, which dismisses an open system panel.
    ///
    /// Notification Center and Control Centre both answer it while items stay concealed, so a
    /// click that dismisses a panel needs no lift of concealment at all.
    private static func postEscape() {
        let source = CGEventSource(stateID: .hidSystemState)
        for down in [true, false] {
            CGEvent(keyboardEventSource: source, virtualKey: 53, keyDown: down)?.post(tap: .cghidEventTap)
        }
    }

    /// Waits for a system item's panel to appear.
    @available(macOS 27.0, *)
    private static func waitForPanel(baseline: Set<Int>, pollsOf50ms: Int) async -> Bool {
        for _ in 0..<pollsOf50ms {
            try? await Task.sleep(for: .milliseconds(50))
            if ItemClick27.panelOpened(before: baseline, windows: windowsForPanelCheck()) {
                return true
            }
        }
        return false
    }

    /// Presses an Accessibility element off the main thread, which the call can block.
    private static func press(_ element: AXUIElement) async {
        await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                _ = AXUIElementPerformAction(element, kAXPressAction as CFString)
                continuation.resume()
            }
        }
    }

    private static func replayClick(at location: CGPoint) {
        let source = CGEventSource(stateID: .hidSystemState)
        for type in [CGEventType.leftMouseDown, .leftMouseUp] {
            guard let event = CGEvent(
                mouseEventSource: source,
                mouseType: type,
                mouseCursorPosition: location,
                mouseButton: .left
            ) else {
                continue
            }
            event.setIntegerValueField(.eventSourceUserData, value: replayedClickMarker)
            event.post(tap: .cghidEventTap)
        }
    }

    // MARK: Handle Show On Hover

    private func handleShowOnHover(appState: AppState, screen: NSScreen, location: MouseHelpers.Location?) {
        // Make sure the "ShowOnHover" feature is enabled.
        //
        // `showOnHoverAllowed` is deliberately *not* checked here. It is cleared
        // when the user clicks in the menu bar, so that hovering does not
        // immediately undo a deliberate click, and it is restored only inside
        // `MenuBarSection.hide()`. Checking it here disabled the hide-on-leave
        // branch below as well — and that branch is what calls `hide()`. The flag
        // therefore latched off the only mechanism that could clear it, leaving
        // the Ice Bar on screen indefinitely: on whatever display it was opened
        // on, while the user worked on another one. It is checked in the reveal
        // branch instead, where it belongs.
        guard appState.settings.general.showOnHover else {
            return
        }

        // Only continue if we have a hidden section (we should).
        guard let hiddenSection = appState.menuBarManager.section(withName: .hidden) else {
            return
        }

        let delay = appState.settings.advanced.showOnHoverDelay

        if hiddenSection.isHidden {
            guard
                appState.menuBarManager.showOnHoverAllowed,
                let location,
                isMouseInsideEmptyMenuBarSpace(appState: appState, screen: screen, location: location)
            else {
                return
            }
            lastEmptyMenuBarPoints[screen.displayID] = location.coreGraphics
            scheduleHoverAction(.show(screen.displayID), after: .seconds(delay)) { [weak self] in
                // Make sure the mouse is still inside.
                guard let self, isMouseInsideEmptyMenuBarSpace(appState: appState, screen: screen) else {
                    return
                }
                hiddenSection.show()
            }
        } else {
            guard
                !isMouseInsideMenuBar(appState: appState, screen: screen, location: location),
                !isMouseInsideIceBar(appState: appState, location: location)
            else {
                return
            }
            scheduleHoverAction(.hide, after: .seconds(delay)) { [weak self] in
                // Make sure the mouse is still outside.
                guard
                    let self,
                    !isMouseInsideMenuBar(appState: appState, screen: screen),
                    !isMouseInsideIceBar(appState: appState)
                else {
                    return
                }
                hiddenSection.hide()
            }
        }
    }

    /// Performs the given show-on-hover action after a delay, unless the same action
    /// is already pending.
    ///
    /// The mouse moves many times a second, and each move used to start a task of its
    /// own. A pending action is only replaced by a different one, so its delay still
    /// counts from the first move that asked for it.
    private func scheduleHoverAction(_ action: HoverAction, after delay: Duration, perform: @escaping () -> Void) {
        if hoverTask?.action == action {
            return
        }
        hoverTask?.task.cancel()
        let task = Task { [weak self] in
            try? await Task.sleep(for: delay)
            guard !Task.isCancelled else {
                return
            }
            self?.hoverTask = nil
            perform()
        }
        hoverTask = (action, task)
    }

    // MARK: Handle Prevent Show On Hover

    private func handlePreventShowOnHover(with event: NSEvent, appState: AppState, screen: NSScreen) {
        guard
            appState.settings.general.showOnHover,
            !appState.settings.general.useIceBar
        else {
            return
        }

        guard let location = event.cgEvent.map(MouseHelpers.Location.init) ?? MouseHelpers.location else {
            return
        }

        guard isMouseInsideMenuBar(appState: appState, screen: screen, location: location) else {
            return
        }

        if isMouseInsideMenuBarItem(appState: appState, screen: screen, location: location) {
            switch event.type {
            case .leftMouseDown:
                if appState.menuBarManager.hasVisibleSection {
                    break
                }
                if isMouseInsideIceIcon(appState: appState, location: location) {
                    break
                }
                return
            case .rightMouseDown:
                if appState.menuBarManager.hasVisibleSection {
                    break
                }
                return
            default:
                return
            }
        } else if isMouseInsideApplicationMenu(appState: appState, screen: screen, location: location) {
            return
        }

        // Mouse is inside the menu bar, outside an item or application
        // menu, so it must be inside an empty menu bar space.
        appState.menuBarManager.showOnHoverAllowed = false
    }

    // MARK: Handle Show On Scroll

    private func handleShowOnScroll(with event: NSEvent, appState: AppState, screen: NSScreen) {
        guard
            appState.settings.general.showOnScroll,
            isMouseInsideMenuBar(appState: appState, screen: screen),
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
    }
}

// MARK: - Helper Methods

extension HIDEventManager {
    /// Returns the best screen to use for event manager calculations.
    /// Uses the screen under the mouse so menu bar hover/click work correctly
    /// with multiple displays (e.g. external monitor).
    func bestScreen(appState: AppState) -> NSScreen? {
        NSScreen.screenWithMouse ?? NSScreen.main
    }

    /// A Boolean value that indicates whether the mouse pointer is within
    /// the bounds of the menu bar.
    func isMouseInsideMenuBar(
        appState: AppState,
        screen: NSScreen,
        location: MouseHelpers.Location? = MouseHelpers.location
    ) -> Bool {
        guard let mouseLocation = location?.appKit else {
            return false
        }

        // Ice icon must be vertically visible. Otherwise, we can infer
        // that the menu bar is hidden and the mouse is not inside.
        //
        // On macOS 27 the icon's window is only a placeholder, and its frame says
        // nothing about the menu bar (measured past a display's left edge, below its
        // bottom, and with no height). The visible frame check below remains.
        if #unavailable(macOS 27.0) {
            guard
                let iceIcon = appState.menuBarManager.controlItem(withName: .visible),
                let iceIconFrame = iceIcon.frame,
                iceIconFrame.maxY <= screen.frame.maxY
            else {
                return false
            }
        }

        // Infer the menu bar frame from the screen frame.
        return mouseLocation.x >= screen.frame.minX &&
        mouseLocation.x <= screen.frame.maxX &&
        mouseLocation.y <= screen.frame.maxY &&
        mouseLocation.y >= screen.visibleFrame.maxY
    }

    /// A Boolean value that indicates whether the mouse pointer is within
    /// the bounds of the current application menu.
    func isMouseInsideApplicationMenu(
        appState: AppState,
        screen: NSScreen,
        location: MouseHelpers.Location? = MouseHelpers.location
    ) -> Bool {
        guard
            let mouseLocation = location?.coreGraphics,
            var applicationMenuFrame = applicationMenuFrame(for: screen)
        else {
            return false
        }
        applicationMenuFrame.size.width += applicationMenuFrame.origin.x - screen.frame.origin.x
        applicationMenuFrame.origin.x = screen.frame.origin.x
        return applicationMenuFrame.contains(mouseLocation)
    }

    /// Returns the frame of the application menu on the given screen.
    ///
    /// Reading the frame takes a round of Accessibility messages to the frontmost app for
    /// each of its menus, and the hit tests run on every mouse move in the menu bar, so the
    /// frame is reused for the same display and menu bar owner for a short while. It is
    /// read again when another app activates or the space changes.
    private func applicationMenuFrame(for screen: NSScreen) -> CGRect? {
        let ownerPID = NSWorkspace.shared.menuBarOwningApplication?.processIdentifier
        if
            let cache = applicationMenuFrameCache,
            cache.displayID == screen.displayID,
            cache.ownerPID == ownerPID,
            ContinuousClock.now < cache.readAt + .seconds(1)
        {
            return cache.frame
        }
        let frame = screen.getApplicationMenuFrame()
        applicationMenuFrameCache = (screen.displayID, ownerPID, frame, .now)
        return frame
    }

    /// A Boolean value that indicates whether the mouse pointer is within
    /// the bounds of a menu bar item.
    func isMouseInsideMenuBarItem(
        appState: AppState,
        screen: NSScreen,
        location: MouseHelpers.Location? = MouseHelpers.location
    ) -> Bool {
        guard let mouseLocation = location?.coreGraphics else {
            return false
        }
        if #available(macOS 27.0, *) {
            // There are no item windows on macOS 27. See `ItemHitTest27`.
            let items = appState.itemManager.itemCache.managedItems.map { item in
                ItemHitTest27.Item(frame: item.bounds, ownerPID: item.ownerPID, isOnScreen: item.isOnScreen)
            }
            // On the display whose bar is not active only MenuBarAgent describes the items.
            // Items that cannot be hidden, like the button that stops a recording, are missing
            // from the cache, and a click on one must not count as a click on empty bar.
            let systemFrames = MenuBarItemProvider27.systemItemFrames()
                + MenuBarItemProvider27.unhideableItemFrames()
                + [MenuBarItemProvider27.overflowButtonFrame()].compactMap { $0 }
                + MenuBarItemProvider27.inactiveDisplayItemFrames(for: screen.displayID)
            return ItemHitTest27.isInsideItem(
                point: mouseLocation,
                items: items,
                concealedPIDs: appState.concealer27.concealedPIDs,
                systemFrames: systemFrames
            )
        }
        return menuBarItemBounds().contains { bounds in
            bounds.contains(mouseLocation)
        }
    }

    /// Returns the bounds of the menu bar item windows on screen, before macOS 27.
    ///
    /// Reading them asks the window server about every item window, and the hit tests
    /// run on every mouse move in the menu bar, so the bounds are reused for a moment.
    private func menuBarItemBounds() -> [CGRect] {
        if
            let cache = menuBarItemBoundsCache,
            ContinuousClock.now < cache.readAt + .milliseconds(200)
        {
            return cache.bounds
        }
        let windowIDs = Bridging.getMenuBarWindowList(option: [.onScreen, .activeSpace, .itemsOnly])
        let bounds = windowIDs.compactMap { windowID in
            Bridging.getWindowBounds(for: windowID)
        }
        menuBarItemBoundsCache = (bounds, .now)
        return bounds
    }

    /// A Boolean value that indicates whether the mouse pointer is within
    /// the bounds of the screen's notch, if it has one.
    ///
    /// If the screen does not have a notch, this property returns `false`.
    func isMouseInsideNotch(
        appState: AppState,
        screen: NSScreen,
        location: MouseHelpers.Location? = MouseHelpers.location
    ) -> Bool {
        guard
            let mouseLocation = location?.appKit,
            var frameOfNotch = screen.frameOfNotch
        else {
            return false
        }
        frameOfNotch.size.height += 1
        return frameOfNotch.contains(mouseLocation)
    }

    /// A Boolean value that indicates whether the mouse pointer is within
    /// the bounds of an empty space in the menu bar.
    func isMouseInsideEmptyMenuBarSpace(
        appState: AppState,
        screen: NSScreen,
        location: MouseHelpers.Location? = MouseHelpers.location
    ) -> Bool {
        guard let location else {
            return false
        }
        guard
            // Cheapest first: the application menu asks the frontmost app through
            // Accessibility, so it comes last.
            isMouseInsideMenuBar(appState: appState, screen: screen, location: location),
            !isMouseInsideNotch(appState: appState, screen: screen, location: location),
            !isMouseInsideMenuBarItem(appState: appState, screen: screen, location: location),
            !isMouseInsideApplicationMenu(appState: appState, screen: screen, location: location)
        else {
            return false
        }
        if #available(macOS 27.0, *) {
            // The gaps between items are part of the items' own run of the bar.
            return !isMouseInsideItemsArea(appState: appState, screen: screen, location: location)
        }
        return true
    }

    /// A Boolean value that indicates whether the mouse pointer rests in the part of the
    /// menu bar that holds items, including the gaps between them.
    @available(macOS 27.0, *)
    func isMouseInsideItemsArea(
        appState: AppState,
        screen: NSScreen,
        location: MouseHelpers.Location? = MouseHelpers.location
    ) -> Bool {
        guard let mouseLocation = location?.coreGraphics else {
            return false
        }
        let items = appState.itemManager.itemCache.managedItems.map { item in
            ItemHitTest27.Item(frame: item.bounds, ownerPID: item.ownerPID, isOnScreen: item.isOnScreen)
        }
        let systemFrames = MenuBarItemProvider27.systemItemFrames()
            + MenuBarItemProvider27.unhideableItemFrames()
            + [MenuBarItemProvider27.overflowButtonFrame()].compactMap { $0 }
        return ItemHitTest27.isInsideItemsArea(
            point: mouseLocation,
            displayBounds: CGDisplayBounds(screen.displayID),
            items: items,
            concealedPIDs: appState.concealer27.concealedPIDs,
            systemFrames: systemFrames,
            rememberedLeftEdge: MenuBarItemProvider27.leftEdge(for: screen.displayID)
        )
    }

    /// A Boolean value that indicates whether the mouse pointer is within
    /// the bounds of the Ice Bar panel.
    func isMouseInsideIceBar(appState: AppState, location: MouseHelpers.Location? = MouseHelpers.location) -> Bool {
        guard let mouseLocation = location?.appKit else {
            return false
        }
        let panel = appState.menuBarManager.iceBarPanel
        // Pad the frame to be more forgiving if the user accidentally
        // moves their mouse outside of the Ice Bar.
        let paddedFrame = panel.frame.insetBy(dx: -15, dy: -15)
        return paddedFrame.contains(mouseLocation)
    }

    /// A Boolean value that indicates whether the mouse pointer is within
    /// the bounds of the Ice icon.
    func isMouseInsideIceIcon(appState: AppState, location: MouseHelpers.Location? = MouseHelpers.location) -> Bool {
        guard
            let visibleSection = appState.menuBarManager.section(withName: .visible),
            let iceIconFrame = visibleSection.controlItem.frame,
            let mouseLocation = location?.appKit
        else {
            return false
        }
        return iceIconFrame.contains(mouseLocation)
    }
}

// MARK: - EventMonitor Helpers

/// Helper protocol to enable group operations across event
/// monitoring types.
@MainActor
private protocol EventMonitorProtocol {
    func start()
    func stop()
}

extension EventMonitor: EventMonitorProtocol { }

extension EventTap: EventMonitorProtocol {
    fileprivate func start() {
        enable()
    }

    fileprivate func stop() {
        disable()
    }
}
