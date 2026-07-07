//
//  MenuBarOverlayPanel.swift
//  Ice
//

import Cocoa
import Combine

// MARK: - Overlay Panel

/// A subclass of `NSPanel` that sits atop the menu bar to alter its appearance.
///
/// The panel is glued to its owning screen via `.stationary + .canJoinAllSpaces +
/// .fullScreenAuxiliary`, mirroring the system menu bar's own behavior. It is
/// never repositioned during Space/fullscreen slide animations; its visibility
/// and frame are recomputed only at steady-state moments (active Space change,
/// presentation-options change, fullscreen-state change, screen-parameters
/// change, config change). The menu bar height is cached on first use and on
/// screen-parameters change so drawing never reads transient WindowServer
/// geometry during a Space transition.
final class MenuBarOverlayPanel: NSPanel {
    /// Flags representing the updatable components of a panel.
    enum UpdateFlag: String, CustomStringConvertible {
        case applicationMenuFrame
        case desktopWallpaper

        var description: String { rawValue }
    }

    /// The visual mode the panel is currently rendering in.
    enum RenderMode: Equatable {
        /// Full menu-bar-height backdrop with optional rounded top corners
        /// drawn just below the menu bar.
        case backdrop
        /// Only the rounded top-corner wedges, drawn flush with the top edge
        /// of the screen. Used when the system menu bar is hidden.
        case topCornersOnly
    }

    /// A context that manages panel update tasks.
    private final class UpdateTaskContext {
        private var tasks = [UpdateFlag: Task<Void, any Error>]()

        /// Sets the task for the given update flag.
        ///
        /// Setting the task cancels the previous task for the flag, if there is one.
        ///
        /// - Parameters:
        ///   - flag: The update flag to set the task for.
        ///   - timeout: The timeout of the task.
        ///   - operation: The operation for the task to perform.
        func setTask(for flag: UpdateFlag, timeout: Duration, operation: @escaping () async throws -> Void) {
            cancelTask(for: flag)
            tasks[flag] = Task.detached(timeout: timeout) {
                try await operation()
            }
        }

        /// Cancels the task for the given update flag.
        ///
        /// - Parameter flag: The update flag to cancel the task for.
        func cancelTask(for flag: UpdateFlag) {
            tasks.removeValue(forKey: flag)?.cancel()
        }
    }

    /// A Boolean value that indicates whether the panel needs to be shown.
    @Published var needsShow = false

    /// A Boolean value that indicates whether the user is dragging a menu bar item.
    @Published var isDraggingMenuBarItem = false

    /// The current visual mode the panel is rendering in. Published so the
    /// content view can request a redraw when it flips.
    @Published private(set) var renderMode: RenderMode = .backdrop

    /// Flags representing the components of the panel currently in need of an update.
    @Published private(set) var updateFlags = Set<UpdateFlag>()

    /// The frame of the application menu.
    @Published private(set) var applicationMenuFrame: CGRect?

    /// The current desktop wallpaper, clipped to the bounds of the menu bar.
    @Published private(set) var desktopWallpaper: CGImage?

    /// Storage for internal observers.
    private var cancellables = Set<AnyCancellable>()

    /// The context that manages panel update tasks.
    private let updateTaskContext = UpdateTaskContext()

    /// Cached menu bar height for this panel's screen. Captured once at init
    /// and refreshed on screen-parameters changes so the visibility/frame
    /// logic never has to read live WindowServer geometry during a Space
    /// transition. The content view reads this for drawing.
    fileprivate var cachedMenuBarHeight: CGFloat

    /// The shared app state.
    private(set) weak var appState: AppState?

    /// The screen that owns the panel.
    let owningScreen: NSScreen

    /// Creates an overlay panel with the given app state and owning screen.
    init(appState: AppState, owningScreen: NSScreen) {
        self.appState = appState
        self.owningScreen = owningScreen
        self.cachedMenuBarHeight = owningScreen.getMenuBarHeight() ?? NSStatusBar.system.thickness
        super.init(
            contentRect: .zero,
            styleMask: [.borderless, .fullSizeContentView, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        self.level = .statusBar
        self.title = "Menu Bar Overlay"
        self.backgroundColor = .clear
        self.hasShadow = false
        self.ignoresMouseEvents = true
        // `.stationary` glues the panel to this physical screen position
        // through Space/fullscreen slide animations, so a swipe between Spaces
        // never tears the overlay off the screen edge mid-animation. The
        // sibling `ScreenBottomCornerOverlayPanel` uses the same set.
        self.collectionBehavior = [.ignoresCycle, .canJoinAllSpaces, .stationary, .fullScreenAuxiliary]
        self.contentView = MenuBarOverlayPanelContentView()
        updateLevel(for: appState.appearanceManager.configuration.current.appearanceKind)
        configureCancellables()
    }

    /// Sets the panel's window level based on the appearance kind. Backdrop
    /// mode sits one below `.statusBar` so status items render on top.
    fileprivate func updateLevel(for kind: MenuBarAppearanceKind) {
        let target: NSWindow.Level = switch kind {
        case .backdrop: NSWindow.Level(rawValue: NSWindow.Level.statusBar.rawValue - 1)
        case .none, .tint: .statusBar
        }
        if self.level != target {
            self.level = target
        }
    }

    private func configureCancellables() {
        var c = Set<AnyCancellable>()

        // The panel joins every Space. On a space switch, refresh visibility
        // for the new steady state and re-arm per-space content updates.
        NSWorkspace.shared.notificationCenter
            .publisher(for: NSWorkspace.activeSpaceDidChangeNotification)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                guard let self, self.updateVisibility() else {
                    return
                }
                self.insertUpdateFlag(.applicationMenuFrame)
                self.insertUpdateFlag(.desktopWallpaper)
            }
            .store(in: &c)

        // Update when light/dark mode changes.
        DistributedNotificationCenter.default()
            .publisher(for: DistributedNotificationCenter.interfaceThemeChangedNotification)
            .debounce(for: 0.1, scheduler: DispatchQueue.main)
            .sink { [weak self] _ in
                guard let self else {
                    return
                }
                updateTaskContext.setTask(for: .desktopWallpaper, timeout: .seconds(5)) {
                    while true {
                        try Task.checkCancellation()
                        self.insertUpdateFlag(.desktopWallpaper)
                        try await Task.sleep(for: .seconds(1))
                    }
                }
            }
            .store(in: &c)

        // Update application menu frame when the menu bar owning or frontmost app changes.
        Publishers.Merge(
            NSWorkspace.shared.publisher(for: \.menuBarOwningApplication, options: .old)
                .combineLatest(NSWorkspace.shared.publisher(for: \.menuBarOwningApplication, options: .new))
                .compactMap { $0 == $1 ? nil : $0 },
            NSWorkspace.shared.publisher(for: \.frontmostApplication, options: .old)
                .combineLatest(NSWorkspace.shared.publisher(for: \.frontmostApplication, options: .new))
                .compactMap { $0 == $1 ? nil : $0 }
        )
        .removeDuplicates()
        .sink { [weak self] _ in
            guard
                let self,
                let appState,
                self.updateVisibility()
            else {
                return
            }
            let displayID = self.owningScreen.displayID
            self.updateTaskContext.setTask(for: .applicationMenuFrame, timeout: .seconds(10)) {
                var hasDoneInitialUpdate = false
                while true {
                    try Task.checkCancellation()
                    guard
                        let latestFrame = appState.menuBarManager.getApplicationMenuFrame(for: displayID),
                        latestFrame != self.applicationMenuFrame
                    else {
                        if hasDoneInitialUpdate {
                            try await Task.sleep(for: .seconds(1))
                        } else {
                            try await Task.sleep(for: .milliseconds(1))
                        }
                        continue
                    }
                    self.insertUpdateFlag(.applicationMenuFrame)
                    hasDoneInitialUpdate = true
                }
            }
            Task {
                try? await Task.sleep(for: .milliseconds(100))
                if self.owningScreen != NSScreen.main {
                    self.updateTaskContext.cancelTask(for: .applicationMenuFrame)
                }
            }
        }
        .store(in: &c)

        // Re-promote the panel whenever this app's own activation changes. The
        // "Hide application menus" feature flips Ice's activation policy
        // (.accessory ↔ .regular), and WindowServer can briefly reshuffle the
        // order of windows at our level during the transition.
        Publishers.Merge(
            NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification),
            NotificationCenter.default.publisher(for: NSApplication.didResignActiveNotification)
        )
        .receive(on: DispatchQueue.main)
        .sink { [weak self] _ in
            guard let self, self.updateVisibility() else {
                return
            }
            self.orderForCurrentLevel()
        }
        .store(in: &c)

        // Special cases for when the user drags an app onto or clicks into another space.
        Publishers.Merge(
            publisher(for: \.isOnActiveSpace)
                .receive(on: DispatchQueue.main)
                .mapToVoid(),
            UniversalEventMonitor.publisher(for: .leftMouseUp)
                .filter { [weak self] _ in self?.isOnActiveSpace ?? false }
                .mapToVoid()
        )
        .debounce(for: 0.05, scheduler: DispatchQueue.main)
        .sink { [weak self] in
            guard let self, self.updateVisibility() else {
                return
            }
            self.insertUpdateFlag(.applicationMenuFrame)
        }
        .store(in: &c)

        NotificationCenter.default
            .publisher(for: NSApplication.didChangeScreenParametersNotification)
            .debounce(for: 0.1, scheduler: DispatchQueue.main)
            .sink { [weak self] _ in
                guard let self else {
                    return
                }
                if let height = self.owningScreen.getMenuBarHeight(), height > 0 {
                    self.cachedMenuBarHeight = height
                }
                self.updateVisibility()
            }
            .store(in: &c)

        // Continually update the desktop wallpaper. Ideally, we would set up an observer
        // for a wallpaper change notification, but macOS doesn't post one anymore.
        Timer.publish(every: 5, on: .main, in: .default)
            .autoconnect()
            .sink { [weak self] _ in
                self?.insertUpdateFlag(.desktopWallpaper)
            }
            .store(in: &c)

        Timer.publish(every: 10, on: .main, in: .default)
            .autoconnect()
            .sink { [weak self] _ in
                self?.insertUpdateFlag(.applicationMenuFrame)
            }
            .store(in: &c)

        $needsShow
            .debounce(for: 0.05, scheduler: DispatchQueue.main)
            .sink { [weak self] needsShow in
                guard let self, needsShow else {
                    return
                }
                defer {
                    self.needsShow = false
                }
                updateVisibility()
            }
            .store(in: &c)

        $updateFlags
            .sink { [weak self] flags in
                guard let self, !flags.isEmpty else {
                    return
                }
                Task {
                    // Must be run async, or this will not remove the flags.
                    self.updateFlags.removeAll()
                }
                let windows = WindowInfo.getOnScreenWindows()
                guard let owningDisplay = self.validate(with: windows) else {
                    return
                }
                performUpdates(for: flags, windows: windows, display: owningDisplay)
            }
            .store(in: &c)

        if let appState {
            // This combines the steady menu-bar policy with transient system
            // presentation options such as Mission Control/Expose.
            appState.menuBarManager.$isMenuBarHiddenBySystem
                .receive(on: DispatchQueue.main)
                .sink { [weak self] _ in
                    self?.updateVisibility()
                }
                .store(in: &c)

            // During Mission Control/Expose, macOS hides the system menu bar
            // even on desktop spaces where it normally remains visible. Treat
            // that as hidden for overlay layout, then restore when it settles.
            appState.menuBarManager.$isMenuBarHiddenBySystemPresentationOptions
                .receive(on: DispatchQueue.main)
                .sink { [weak self] _ in
                    self?.updateVisibility()
                }
                .store(in: &c)

            // Re-evaluate when the active space flips between desktop and
            // fullscreen. This only fires once per transition, at the end.
            appState.$isActiveSpaceFullscreen
                .receive(on: DispatchQueue.main)
                .sink { [weak self] _ in
                    self?.updateVisibility()
                }
                .store(in: &c)

            // Keep the window level in sync with the current appearance kind.
            appState.appearanceManager.$configuration
                .map { $0.current.appearanceKind }
                .removeDuplicates()
                .sink { [weak self] kind in
                    self?.updateLevel(for: kind)
                }
                .store(in: &c)

            for section in appState.menuBarManager.sections {
                section.controlItem.$windowFrame
                    .receive(on: DispatchQueue.main)
                    .sink { [weak self] _ in
                        self?.insertUpdateFlag(.applicationMenuFrame)
                    }
                    .store(in: &c)
            }
        }

        cancellables = c
    }

    /// Inserts the given update flag into the panel's current list of update flags.
    private func insertUpdateFlag(_ flag: UpdateFlag) {
        updateFlags.insert(flag)
    }

    /// Re-evaluates the panel's visibility and frame from steady-state inputs
    /// only: the active-space menu-bar policy, fullscreen state, and
    /// configuration. This never queries live WindowServer geometry, so it is
    /// safe to call during the brief window after
    /// `activeSpaceDidChangeNotification` where the menu bar window has not
    /// yet finished settling.
    ///
    /// Returns `true` if the panel is visible after the update.
    @discardableResult
    private func updateVisibility() -> Bool {
        guard
            let appState,
            !appState.isPreview,
            appState.appearanceManager.overlayPanels.contains(self)
        else {
            return false
        }

        let isMenuBarHidden = appState.menuBarManager.isMenuBarHiddenBySystem(on: owningScreen)
        let isFullscreen = appState.menuBarManager.isSpaceFullscreen(on: owningScreen)
        let info = appState.appearanceManager.configuration.effectiveScreenShapeInfo(for: owningScreen)
        let cornerRadius = hasActiveRoundedTopScreenCorners() ? info.cornerRadius : 0

        // Notched displays cannot use corners-only mode. When the system menu
        // bar is hidden in this screen's current space, order the panel out so
        // it cannot reappear above the status items during a menu-bar peek.
        if owningScreen.hasNotch {
            renderMode = .backdrop
            if isMenuBarHidden {
                alphaValue = 0
                updateFlags.removeAll()
                orderOut(nil)
                return false
            }
            applyBackdropFrame(cornerExtension: cornerRadius)
            orderForCurrentLevel()
            alphaValue = 1
            updateFlags = [.applicationMenuFrame, .desktopWallpaper]
            return true
        }

        // Non-notched displays switch between backdrop and corners-only
        // depending on the steady-state menu-bar visibility for this screen's
        // current space. Corners-only is only drawn when rounded top corners are
        // configured and the fullscreen setting allows it.
        let canShowFullscreenCorners = !isFullscreen || info.showInFullscreen
        let shouldShowCornersOnly = isMenuBarHidden && cornerRadius > 0 && canShowFullscreenCorners

        if isMenuBarHidden {
            if shouldShowCornersOnly {
                renderMode = .topCornersOnly
                applyCornersOnlyFrame(cornerExtension: cornerRadius)
                orderFrontRegardless()
                alphaValue = 1
                updateFlags.removeAll()
                contentView?.needsDisplay = true
                return true
            }
            renderMode = .backdrop
            orderOut(nil)
            return false
        }

        renderMode = .backdrop
        applyBackdropFrame(cornerExtension: cornerRadius)
        orderForCurrentLevel()
        alphaValue = 1
        updateFlags = [.applicationMenuFrame, .desktopWallpaper]
        return true
    }

    /// Orders the panel appropriately for its current level. Backdrop panels
    /// sit below the system menu bar window so status items stay on top even
    /// after Mission Control/Expose reshuffles WindowServer ordering.
    private func orderForCurrentLevel() {
        guard
            level.rawValue < NSWindow.Level.statusBar.rawValue,
            let menuBarWindow = WindowInfo.getMenuBarWindow(for: owningScreen.displayID)
        else {
            orderFrontRegardless()
            return
        }
        order(.below, relativeTo: Int(menuBarWindow.windowID))
    }

    /// Positions the panel as a full-height backdrop covering the menu bar
    /// with an optional rounded-corner extension below it.
    private func applyBackdropFrame(cornerExtension: CGFloat) {
        let menuBarHeight = cachedMenuBarHeight
        let newFrame = CGRect(
            x: owningScreen.frame.minX,
            y: (owningScreen.frame.maxY - menuBarHeight) - 5 - cornerExtension,
            width: owningScreen.frame.width,
            height: menuBarHeight + 5 + cornerExtension
        )
        if frame != newFrame {
            setFrame(newFrame, display: false)
        }
    }

    /// Positions the panel as just the rounded top-corner wedges sitting flush
    /// against the screen's top edge.
    private func applyCornersOnlyFrame(cornerExtension: CGFloat) {
        let newFrame = CGRect(
            x: owningScreen.frame.minX,
            y: owningScreen.frame.maxY - cornerExtension,
            width: owningScreen.frame.width,
            height: cornerExtension
        )
        if frame != newFrame {
            setFrame(newFrame, display: false)
        }
    }

    /// Returns whether rounded top screen corners are active for this panel's
    /// screen and current configuration.
    private func hasActiveRoundedTopScreenCorners() -> Bool {
        guard let appearanceManager = appState?.appearanceManager else {
            return false
        }
        return appearanceManager.hasActiveRoundedTopScreenCorners(
            for: owningScreen,
            in: appearanceManager.configuration
        )
    }

    /// Validates the panel for an update pass. Returns the owning display ID
    /// when it is safe to refresh application-menu/wallpaper state, otherwise
    /// `nil`. Updates only happen in backdrop mode; corners-only mode does not
    /// depend on the menu bar window being valid.
    private func validate(with windows: [WindowInfo]) -> CGDirectDisplayID? {
        guard let appState else {
            return nil
        }
        guard renderMode == .backdrop else {
            return nil
        }
        let owningDisplay = owningScreen.displayID
        guard appState.menuBarManager.hasValidMenuBar(in: windows, for: owningDisplay) else {
            return nil
        }
        return owningDisplay
    }

    /// Stores the frame of the menu bar's application menu.
    private func updateApplicationMenuFrame(for display: CGDirectDisplayID) {
        guard let menuBarManager = appState?.menuBarManager else {
            return
        }
        applicationMenuFrame = menuBarManager.getApplicationMenuFrame(for: display)
    }

    /// Stores the area of the desktop wallpaper that is under the menu bar
    /// of the given display.
    private func updateDesktopWallpaper(for display: CGDirectDisplayID, with windows: [WindowInfo]) {
        guard
            let wallpaperWindow = WindowInfo.getWallpaperWindow(from: windows, for: display),
            let menuBarWindow = WindowInfo.getMenuBarWindow(from: windows, for: display)
        else {
            return
        }
        let wallpaper = ScreenCapture.captureWindow(wallpaperWindow.windowID, screenBounds: menuBarWindow.frame)
        if desktopWallpaper?.dataProvider?.data != wallpaper?.dataProvider?.data {
            desktopWallpaper = wallpaper
        }
    }

    /// Updates the panel to prepare for display.
    private func performUpdates(for flags: Set<UpdateFlag>, windows: [WindowInfo], display: CGDirectDisplayID) {
        if flags.contains(.applicationMenuFrame) {
            updateApplicationMenuFrame(for: display)
        }
        if flags.contains(.desktopWallpaper) {
            updateDesktopWallpaper(for: display, with: windows)
        }
    }

    override func isAccessibilityElement() -> Bool {
        return false
    }
}

// MARK: - Content View

private final class MenuBarOverlayPanelContentView: NSView {
    @Published private var fullConfiguration: MenuBarAppearanceConfigurationV2 = .defaultConfiguration

    @Published private var previewConfiguration: MenuBarAppearancePartialConfiguration?

    private var cancellables = Set<AnyCancellable>()

    /// The overlay panel that contains the content view.
    private var overlayPanel: MenuBarOverlayPanel? {
        window as? MenuBarOverlayPanel
    }

    /// The currently displayed configuration.
    private var configuration: MenuBarAppearancePartialConfiguration {
        previewConfiguration ?? fullConfiguration.current
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        configureCancellables()
    }

    private func configureCancellables() {
        var c = Set<AnyCancellable>()

        if let overlayPanel {
            if let appState = overlayPanel.appState {
                appState.appearanceManager.$configuration
                    .removeDuplicates()
                    .assign(to: &$fullConfiguration)

                appState.appearanceManager.$previewConfiguration
                    .removeDuplicates()
                    .assign(to: &$previewConfiguration)

                for section in appState.menuBarManager.sections {
                    // Redraw whenever the window frame of a control item changes.
                    //
                    // - NOTE: A previous attempt was made to redraw the view when the
                    //   section's `isHidden` property was changed. This would be semantically
                    //   ideal, but the property sometimes changes before the menu bar items
                    //   are actually updated on-screen. Since the view's drawing process relies
                    //   on getting an accurate position of each menu bar item, we need to use
                    //   something that publishes its changes only after the items are updated.
                    section.controlItem.$windowFrame
                        .receive(on: DispatchQueue.main)
                        .sink { [weak self] _ in
                            self?.needsDisplay = true
                        }
                        .store(in: &c)

                    // Redraw whenever the visibility of a control item changes.
                    //
                    // - NOTE: If the "ShowSectionDividers" setting is disabled, the window
                    //   frame does not update when the section is hidden or shown, but the
                    //   visibility does. We observe both to ensure the update occurs.
                    section.controlItem.$isVisible
                        .receive(on: DispatchQueue.main)
                        .sink { [weak self] _ in
                            self?.needsDisplay = true
                        }
                        .store(in: &c)
                }
            }

            // Fade out whenever a menu bar item is being dragged.
            overlayPanel.$isDraggingMenuBarItem
                .removeDuplicates()
                .sink { [weak self] isDragging in
                    if isDragging {
                        self?.animator().alphaValue = 0
                    } else {
                        self?.animator().alphaValue = 1
                    }
                }
                .store(in: &c)
            // Redraw whenever the application menu frame changes.
            overlayPanel.$applicationMenuFrame
                .sink { [weak self] _ in
                    self?.needsDisplay = true
                }
                .store(in: &c)
            // Redraw whenever the desktop wallpaper changes.
            overlayPanel.$desktopWallpaper
                .sink { [weak self] _ in
                    self?.needsDisplay = true
                }
                .store(in: &c)
            // Redraw when the panel switches between backdrop and corners-only modes.
            overlayPanel.$renderMode
                .removeDuplicates()
                .sink { [weak self] _ in
                    self?.needsDisplay = true
                }
                .store(in: &c)
        }

        // Redraw whenever the configurations change.
        $fullConfiguration.mapToVoid()
            .merge(with: $previewConfiguration.mapToVoid())
            .sink { [weak self] _ in
                self?.needsDisplay = true
            }
            .store(in: &c)

        cancellables = c
    }

    /// Returns a path in the given rectangle, with the given end caps,
    /// and inset by the given amounts.
    private func shapePath(in rect: CGRect, leadingEndCap: MenuBarEndCap, trailingEndCap: MenuBarEndCap, screen: NSScreen) -> NSBezierPath {
        let insetRect: CGRect = if !screen.hasNotch {
            switch (leadingEndCap, trailingEndCap) {
            case (.square, .square):
                CGRect(x: rect.origin.x, y: rect.origin.y + 1, width: rect.width, height: rect.height - 2)
            case (.square, .round):
                CGRect(x: rect.origin.x, y: rect.origin.y + 1, width: rect.width - 1, height: rect.height - 2)
            case (.round, .square):
                CGRect(x: rect.origin.x + 1, y: rect.origin.y + 1, width: rect.width - 1, height: rect.height - 2)
            case (.round, .round):
                CGRect(x: rect.origin.x + 1, y: rect.origin.y + 1, width: rect.width - 2, height: rect.height - 2)
            }
        } else {
            rect
        }

        let shapeBounds = CGRect(
            x: insetRect.minX + insetRect.height / 2,
            y: insetRect.minY,
            width: insetRect.width - insetRect.height,
            height: insetRect.height
        )
        let leadingEndCapBounds = CGRect(
            x: insetRect.minX,
            y: insetRect.minY,
            width: insetRect.height,
            height: insetRect.height
        )
        let trailingEndCapBounds = CGRect(
            x: insetRect.maxX - insetRect.height,
            y: insetRect.minY,
            width: insetRect.height,
            height: insetRect.height
        )

        var path = NSBezierPath(rect: shapeBounds)

        path = switch leadingEndCap {
        case .square: path.union(NSBezierPath(rect: leadingEndCapBounds))
        case .round: path.union(NSBezierPath(ovalIn: leadingEndCapBounds))
        }

        path = switch trailingEndCap {
        case .square: path.union(NSBezierPath(rect: trailingEndCapBounds))
        case .round: path.union(NSBezierPath(ovalIn: trailingEndCapBounds))
        }

        return path
    }

    /// Returns a path for the ``MenuBarShapeKind/full`` shape kind.
    private func pathForFullShape(in rect: CGRect, info: MenuBarFullShapeInfo, isInset: Bool, screen: NSScreen) -> NSBezierPath {
        guard let appearanceManager = overlayPanel?.appState?.appearanceManager else {
            return NSBezierPath()
        }
        var rect = rect
        let shouldInset = isInset && screen.hasNotch
        if shouldInset {
            rect = rect.insetBy(dx: 0, dy: appearanceManager.menuBarInsetAmount)
            if info.leadingEndCap == .round {
                rect.origin.x += appearanceManager.menuBarInsetAmount
                rect.size.width -= appearanceManager.menuBarInsetAmount
            }
            if info.trailingEndCap == .round {
                rect.size.width -= appearanceManager.menuBarInsetAmount
            }
        }
        return shapePath(
            in: rect,
            leadingEndCap: info.leadingEndCap,
            trailingEndCap: info.trailingEndCap,
            screen: screen
        )
    }

    /// Returns a path for the ``MenuBarShapeKind/split`` shape kind.
    private func pathForSplitShape(in rect: CGRect, info: MenuBarSplitShapeInfo, isInset: Bool, screen: NSScreen) -> NSBezierPath {
        guard let appearanceManager = overlayPanel?.appState?.appearanceManager else {
            return NSBezierPath()
        }
        var rect = rect
        let shouldInset = isInset && screen.hasNotch
        if shouldInset {
            rect = rect.insetBy(dx: 0, dy: appearanceManager.menuBarInsetAmount)
            if info.leading.leadingEndCap == .round {
                rect.origin.x += appearanceManager.menuBarInsetAmount
                rect.size.width -= appearanceManager.menuBarInsetAmount
            }
            if info.trailing.trailingEndCap == .round {
                rect.size.width -= appearanceManager.menuBarInsetAmount
            }
        }
        let leadingPathBounds: CGRect = {
            guard
                var maxX = overlayPanel?.applicationMenuFrame?.width,
                maxX > 0
            else {
                return .zero
            }
            if shouldInset {
                maxX += 10
                if info.leading.leadingEndCap == .square {
                    maxX += appearanceManager.menuBarInsetAmount
                }
            } else {
                maxX += 20
            }
            return CGRect(x: rect.minX, y: rect.minY, width: maxX, height: rect.height)
        }()
        let trailingPathBounds: CGRect = {
            let items = MenuBarItem.getMenuBarItems(on: screen.displayID, onScreenOnly: true, activeSpaceOnly: false)
            guard !items.isEmpty else {
                return .zero
            }
            let totalWidth = items.reduce(into: 0) { width, item in
                width += item.frame.width
            }
            var position = rect.maxX - totalWidth
            if shouldInset {
                position += 4
                if info.trailing.trailingEndCap == .square {
                    position -= appearanceManager.menuBarInsetAmount
                }
            } else {
                position -= 7
            }
            return CGRect(x: position, y: rect.minY, width: rect.maxX - position, height: rect.height)
        }()

        if leadingPathBounds == .zero || trailingPathBounds == .zero || leadingPathBounds.intersects(trailingPathBounds) {
            return shapePath(
                in: rect,
                leadingEndCap: info.leading.leadingEndCap,
                trailingEndCap: info.trailing.trailingEndCap,
                screen: screen
            )
        } else {
            let leadingPath = shapePath(
                in: leadingPathBounds,
                leadingEndCap: info.leading.leadingEndCap,
                trailingEndCap: info.leading.trailingEndCap,
                screen: screen
            )
            let trailingPath = shapePath(
                in: trailingPathBounds,
                leadingEndCap: info.trailing.leadingEndCap,
                trailingEndCap: info.trailing.trailingEndCap,
                screen: screen
            )
            let path = NSBezierPath()
            path.append(leadingPath)
            path.append(trailingPath)
            return path
        }
    }

    /// Returns the bounds that the view's drawn content can occupy. This is
    /// always exactly the menu bar's rectangle at the top of the panel,
    /// regardless of any extra extension the panel has reserved for wedges.
    private func getDrawableBounds() -> CGRect {
        let menuBarHeight = currentMenuBarHeight()
        return CGRect(
            x: bounds.origin.x,
            y: bounds.maxY - menuBarHeight,
            width: bounds.width,
            height: menuBarHeight
        )
    }

    /// Returns the corner-wedge extension currently reserved by the panel's
    /// frame, derived from frame geometry so it stays in sync without polling.
    /// In corners-only mode the entire panel height is the wedge extension.
    /// In backdrop mode the wedge extension is what remains below the menu
    /// bar and the 5pt shadow strip.
    private func currentCornerExtension() -> CGFloat {
        guard let overlayPanel else {
            return 0
        }
        switch overlayPanel.renderMode {
        case .topCornersOnly:
            return bounds.height
        case .backdrop:
            return max(0, bounds.height - currentMenuBarHeight() - 5)
        }
    }

    /// Returns the menu bar height appropriate for the panel's current frame.
    /// Zero in corners-only mode (the menu bar itself is hidden in that
    /// state); otherwise the panel's cached menu bar height for its screen.
    private func currentMenuBarHeight() -> CGFloat {
        guard let overlayPanel else {
            return 0
        }
        if overlayPanel.renderMode == .topCornersOnly {
            return 0
        }
        return overlayPanel.cachedMenuBarHeight
    }

    /// Returns whether rounded top screen corners should be drawn for the
    /// current configuration on the panel's owning screen.
    private func shouldDrawTopScreenCorners() -> Bool {
        guard
            let appearanceManager = overlayPanel?.appState?.appearanceManager,
            let screen = overlayPanel?.owningScreen
        else {
            return false
        }
        return appearanceManager.hasActiveRoundedTopScreenCorners(for: screen, in: fullConfiguration)
    }

    /// Returns a path containing the menu bar rect unioned with the left and
    /// right top-corner wedges that sit just below it.
    private func pathForMenuBarWithTopScreenCorners(menuBarRect: CGRect, radius: CGFloat) -> NSBezierPath {
        let leftWedge = NSBezierPath()
        leftWedge.move(to: CGPoint(x: menuBarRect.minX, y: menuBarRect.minY))
        leftWedge.line(to: CGPoint(x: menuBarRect.minX, y: menuBarRect.minY - radius))
        leftWedge.appendArc(
            withCenter: CGPoint(x: menuBarRect.minX + radius, y: menuBarRect.minY - radius),
            radius: radius,
            startAngle: 180,
            endAngle: 90,
            clockwise: true
        )
        leftWedge.close()

        let rightWedge = NSBezierPath()
        rightWedge.move(to: CGPoint(x: menuBarRect.maxX, y: menuBarRect.minY))
        rightWedge.line(to: CGPoint(x: menuBarRect.maxX, y: menuBarRect.minY - radius))
        rightWedge.appendArc(
            withCenter: CGPoint(x: menuBarRect.maxX - radius, y: menuBarRect.minY - radius),
            radius: radius,
            startAngle: 0,
            endAngle: 90,
            clockwise: false
        )
        rightWedge.close()

        return NSBezierPath(rect: menuBarRect)
            .union(leftWedge)
            .union(rightWedge)
    }

    /// Draws the tint defined by the given configuration in the given rectangle.
    private func drawTint(in rect: CGRect) {
        switch configuration.appearanceKind {
        case .none:
            return
        case .tint:
            // Tint mode renders above status items at a fixed 20% opacity so the
            // icons stay legible.
            switch configuration.tintKind {
            case .none:
                break
            case .solid:
                if let tintColor = NSColor(cgColor: configuration.tintColor)?.withAlphaComponent(0.2) {
                    tintColor.setFill()
                    rect.fill()
                }
            case .gradient:
                if let tintGradient = configuration.tintGradient.withAlphaComponent(0.2).nsGradient {
                    tintGradient.draw(in: rect, angle: 0)
                }
            }
        case .backdrop:
            // Backdrop mode renders beneath status items, so we use the color's
            // stored alpha verbatim — user-controllable, defaulting to opaque.
            switch configuration.tintKind {
            case .none:
                break
            case .solid:
                if let tintColor = NSColor(cgColor: configuration.tintColor) {
                    tintColor.setFill()
                    rect.fill()
                }
            case .gradient:
                if let tintGradient = configuration.tintGradient.nsGradient {
                    tintGradient.draw(in: rect, angle: 0)
                }
            }
        }
    }

    override func draw(_ dirtyRect: NSRect) {
        guard
            let overlayPanel,
            let context = NSGraphicsContext.current
        else {
            return
        }

        let drawableBounds = getDrawableBounds()

        if overlayPanel.renderMode == .topCornersOnly {
            let cornerExt = currentCornerExtension()
            let drawCorners = shouldDrawTopScreenCorners() && cornerExt > 0
            guard drawCorners else {
                return
            }
            let combined = pathForMenuBarWithTopScreenCorners(
                menuBarRect: CGRect(
                    x: bounds.minX,
                    y: bounds.maxY,
                    width: bounds.width,
                    height: 0
                ),
                radius: cornerExt
            )
            context.saveGraphicsState()
            combined.setClip()
            drawTint(in: bounds)
            context.restoreGraphicsState()
            return
        }

        let shapePath = switch fullConfiguration.shapeKind {
        case .none:
            NSBezierPath(rect: drawableBounds)
        case .full:
            pathForFullShape(
                in: drawableBounds,
                info: fullConfiguration.fullShapeInfo,
                isInset: fullConfiguration.isInset,
                screen: overlayPanel.owningScreen
            )
        case .split:
            pathForSplitShape(
                in: drawableBounds,
                info: fullConfiguration.splitShapeInfo,
                isInset: fullConfiguration.isInset,
                screen: overlayPanel.owningScreen
            )
        }

        var hasBorder = false

        switch fullConfiguration.shapeKind {
        case .none:
            let cornerExt = currentCornerExtension()
            let drawCorners = shouldDrawTopScreenCorners() && cornerExt > 0

            if configuration.hasShadow {
                let gradient = NSGradient(
                    colors: [
                        NSColor(white: 0.0, alpha: 0.0),
                        NSColor(white: 0.0, alpha: 0.2),
                    ]
                )
                let shadowBounds = CGRect(
                    x: bounds.minX,
                    y: bounds.minY,
                    width: bounds.width,
                    height: 5
                )
                gradient?.draw(in: shadowBounds, angle: 90)
            }

            if drawCorners {
                let combined = pathForMenuBarWithTopScreenCorners(
                    menuBarRect: drawableBounds,
                    radius: cornerExt
                )
                context.saveGraphicsState()
                combined.setClip()
                drawTint(in: combined.bounds)
                context.restoreGraphicsState()
            } else {
                drawTint(in: drawableBounds)
            }

            if configuration.hasBorder {
                let borderBounds = CGRect(
                    x: bounds.minX,
                    y: drawableBounds.minY,
                    width: bounds.width,
                    height: configuration.borderWidth
                )
                NSColor(cgColor: configuration.borderColor)?.setFill()
                NSBezierPath(rect: borderBounds).fill()
            }
        case .full, .split:
            if let desktopWallpaper = overlayPanel.desktopWallpaper {
                context.saveGraphicsState()
                defer {
                    context.restoreGraphicsState()
                }

                let invertedClipPath = NSBezierPath(rect: drawableBounds)
                invertedClipPath.append(shapePath.reversed)
                invertedClipPath.setClip()

                context.cgContext.draw(desktopWallpaper, in: drawableBounds)
            }

            if configuration.hasShadow {
                context.saveGraphicsState()
                defer {
                    context.restoreGraphicsState()
                }

                let shadowClipPath = NSBezierPath(rect: bounds)
                shadowClipPath.append(shapePath.reversed)
                shadowClipPath.setClip()

                shapePath.drawShadow(color: .black.withAlphaComponent(0.5), radius: 5)
            }

            if configuration.hasBorder {
                hasBorder = true
            }

            do {
                context.saveGraphicsState()
                defer {
                    context.restoreGraphicsState()
                }

                shapePath.setClip()

                drawTint(in: drawableBounds)
            }

            if
                hasBorder,
                let borderColor = NSColor(cgColor: configuration.borderColor)
            {
                context.saveGraphicsState()
                defer {
                    context.restoreGraphicsState()
                }

                let borderPath = switch fullConfiguration.shapeKind {
                case .none:
                    NSBezierPath(rect: drawableBounds)
                case .full:
                    pathForFullShape(
                        in: drawableBounds,
                        info: fullConfiguration.fullShapeInfo,
                        isInset: fullConfiguration.isInset,
                        screen: overlayPanel.owningScreen
                    )
                case .split:
                    pathForSplitShape(
                        in: drawableBounds,
                        info: fullConfiguration.splitShapeInfo,
                        isInset: fullConfiguration.isInset,
                        screen: overlayPanel.owningScreen
                    )
                }

                // HACK: Insetting a path to get an "inside" stroke is surprisingly
                // difficult. We can fake the correct line width by doubling it, as
                // anything outside the shape path will be clipped.
                borderPath.lineWidth = configuration.borderWidth * 2
                borderPath.setClip()

                borderColor.setStroke()
                borderPath.stroke()
            }
        }
    }
}

// MARK: - Logger
private extension Logger {
    static let overlayPanel = Logger(category: "MenuBarOverlayPanel")
}
