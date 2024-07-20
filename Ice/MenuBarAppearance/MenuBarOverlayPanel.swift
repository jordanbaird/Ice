//
//  MenuBarOverlayPanel.swift
//  Ice
//

import Cocoa
import Combine
import OSLog

// MARK: - Overlay Panel

/// A subclass of `NSPanel` that sits atop the menu bar to alter its appearance.
class MenuBarOverlayPanel: NSPanel {
    /// Flags representing the updatable components of a panel.
    enum UpdateFlag: String, CustomStringConvertible {
        case applicationMenuFrame
        case desktopWallpaper

        var description: String { rawValue }
    }

    /// The kind of validation that occurs before an update.
    private enum ValidationKind {
        case showing
        case updates
    }

    /// A context that manages panel update tasks.
    private class UpdateTaskContext {
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

    private var cancellables = Set<AnyCancellable>()

    /// The context that manages panel update tasks.
    private let updateTaskContext = UpdateTaskContext()

    /// The shared app state.
    private(set) weak var appState: AppState?

    /// The screen that owns the panel.
    let owningScreen: NSScreen

    /// A Boolean value that indicates whether the panel needs to be shown.
    @Published var needsShow = false

    /// A Boolean value that indicates whether the user is dragging a menu bar item.
    @Published var isDraggingMenuBarItem = false

    /// Flags representing the components of the panel currently in need of an update.
    @Published private(set) var updateFlags = Set<UpdateFlag>()

    /// The frame of the application menu.
    @Published private(set) var applicationMenuFrame: CGRect?

    /// The current desktop wallpaper, clipped to the bounds of the menu bar.
    @Published private(set) var desktopWallpaper: CGImage?

    /// Creates an overlay panel with the given app state and owning screen.
    init(appState: AppState, owningScreen: NSScreen) {
        self.appState = appState
        self.owningScreen = owningScreen
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
        self.collectionBehavior = [.fullScreenNone, .ignoresCycle, .moveToActiveSpace]
        self.contentView = MenuBarOverlayPanelContentView()
        configureCancellables()
    }

    private func configureCancellables() {
        var c = Set<AnyCancellable>()

        // show the panel on the active space
        NSWorkspace.shared.notificationCenter
            .publisher(for: NSWorkspace.activeSpaceDidChangeNotification)
            .debounce(for: 0.1, scheduler: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.needsShow = true
            }
            .store(in: &c)

        // update when light/dark mode changes
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

        // update application menu frame when the menu bar owning or frontmost app changes
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
                let appState
            else {
                return
            }
            let displayID = owningScreen.displayID
            updateTaskContext.setTask(for: .applicationMenuFrame, timeout: .seconds(10)) {
                while true {
                    try Task.checkCancellation()
                    guard
                        let latestFrame = appState.menuBarManager.getApplicationMenuFrame(for: displayID),
                        latestFrame != self.applicationMenuFrame
                    else {
                        try await Task.sleep(for: .milliseconds(1))
                        continue
                    }
                    self.insertUpdateFlag(.applicationMenuFrame)
                    return
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

        // special cases for when the user drags an app onto or clicks into another space
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
            self?.insertUpdateFlag(.applicationMenuFrame)
        }
        .store(in: &c)

        // continually update the desktop wallpaper; ideally, we would set up an observer
        // for a wallpaper change notification, but macOS doesn't post one anymore
        Timer.publish(every: 5, on: .main, in: .default)
            .autoconnect()
            .sink { [weak self] _ in
                self?.insertUpdateFlag(.desktopWallpaper)
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
                show()
            }
            .store(in: &c)

        $updateFlags
            .sink { [weak self] flags in
                guard let self, !flags.isEmpty else {
                    return
                }
                Task {
                    // must be run async, or this will not remove the flags
                    self.updateFlags.removeAll()
                }
                let windows = WindowInfo.getOnScreenWindows()
                guard let owningDisplay = self.validate(for: .updates, with: windows) else {
                    return
                }
                performUpdates(for: flags, windows: windows, display: owningDisplay)
            }
            .store(in: &c)

        if let appState {
            appState.menuBarManager.$isMenuBarHiddenBySystem
                .sink { [weak self] isHidden in
                    self?.alphaValue = isHidden ? 0 : 1
                }
                .store(in: &c)
        }

        cancellables = c
    }

    /// Inserts the given update flag into the panel's current list of update flags.
    private func insertUpdateFlag(_ flag: UpdateFlag) {
        updateFlags.insert(flag)
    }

    /// Performs validation for the given validation kind. Returns the panel's
    /// owning display if successful. Returns `nil` on failure.
    private func validate(for kind: ValidationKind, with windows: [WindowInfo]) -> CGDirectDisplayID? {
        lazy var actionMessage = switch kind {
        case .showing: "Preventing overlay panel from showing."
        case .updates: "Preventing overlay panel from updating."
        }
        guard let appState else {
            Logger.overlayPanel.debug("No app state. \(actionMessage)")
            return nil
        }
        guard !appState.menuBarManager.isMenuBarHiddenBySystemUserDefaults else {
            Logger.overlayPanel.debug("Menu bar is hidden by system. \(actionMessage)")
            return nil
        }
        guard !appState.isActiveSpaceFullscreen else {
            Logger.overlayPanel.debug("Active space is fullscreen. \(actionMessage)")
            return nil
        }
        let owningDisplay = owningScreen.displayID
        guard appState.menuBarManager.hasValidMenuBar(in: windows, for: owningDisplay) else {
            Logger.overlayPanel.debug("No valid menu bar found. \(actionMessage)")
            return nil
        }
        return owningDisplay
    }

    /// Stores the frame of the menu bar's application menu.
    private func updateApplicationMenuFrame(for display: CGDirectDisplayID) {
        guard
            let menuBarManager = appState?.menuBarManager,
            !menuBarManager.isMenuBarHiddenBySystem
        else {
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
        let wallpaper = Bridging.captureWindow(wallpaperWindow.windowID, screenBounds: menuBarWindow.frame)
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

    /// Shows the panel.
    private func show() {
        guard
            let appState,
            !appState.isPreview
        else {
            return
        }

        guard appState.menuBarManager.appearanceManager.overlayPanels.contains(self) else {
            Logger.overlayPanel.warning("Overlay panel \(self) not retained")
            return
        }

        guard let menuBarHeight = owningScreen.getMenuBarHeight() else {
            return
        }

        let newFrame = CGRect(
            x: owningScreen.frame.minX,
            y: (owningScreen.frame.maxY - menuBarHeight) - 5,
            width: owningScreen.frame.width,
            height: menuBarHeight + 5
        )

        alphaValue = 0
        setFrame(newFrame, display: false)
        orderFrontRegardless()

        updateFlags = [.applicationMenuFrame, .desktopWallpaper]

        if !appState.menuBarManager.isMenuBarHiddenBySystem {
            animator().alphaValue = 1
        }
    }

    override func isAccessibilityElement() -> Bool {
        return false
    }
}

// MARK: - Content View

private class MenuBarOverlayPanelContentView: NSView {
    private var cancellables = Set<AnyCancellable>()

    @Published private var configuration: MenuBarAppearanceConfiguration = .defaultConfiguration

    /// The overlay panel that contains the content view.
    private var overlayPanel: MenuBarOverlayPanel? {
        window as? MenuBarOverlayPanel
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        configureCancellables()
    }

    private func configureCancellables() {
        var c = Set<AnyCancellable>()

        if let overlayPanel {
            if let appState = overlayPanel.appState {
                appState.menuBarManager.appearanceManager.$configuration
                    .removeDuplicates()
                    .assign(to: &$configuration)

                for section in appState.menuBarManager.sections {
                    // redraw whenever the window frame of a control item changes
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

                    // redraw whenever the visibility of a control item changes
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

            // fade out whenever a menu bar item is being dragged
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
            // redraw whenever the application menu frame changes
            overlayPanel.$applicationMenuFrame
                .sink { [weak self] _ in
                    self?.needsDisplay = true
                }
                .store(in: &c)
            // redraw whenever the desktop wallpaper changes
            overlayPanel.$desktopWallpaper
                .sink { [weak self] _ in
                    self?.needsDisplay = true
                }
                .store(in: &c)
        }

        // redraw whenever the configuration changes
        $configuration
            .sink { [weak self] _ in
                self?.needsDisplay = true
            }
            .store(in: &c)

        cancellables = c
    }

    /// Returns a path in the given rectangle, with the given end caps,
    /// and inset by the given amounts.
    private func shapePath(in rect: CGRect, leadingEndCap: MenuBarEndCap, trailingEndCap: MenuBarEndCap) -> NSBezierPath {
        let insetRect: CGRect = switch (leadingEndCap, trailingEndCap) {
        case (.square, .square):
            CGRect(x: rect.origin.x, y: rect.origin.y + 1, width: rect.width, height: rect.height - 2)
        case (.square, .round):
            CGRect(x: rect.origin.x, y: rect.origin.y + 1, width: rect.width - 1, height: rect.height - 2)
        case (.round, .square):
            CGRect(x: rect.origin.x + 1, y: rect.origin.y + 1, width: rect.width - 1, height: rect.height - 2)
        case (.round, .round):
            CGRect(x: rect.origin.x + 1, y: rect.origin.y + 1, width: rect.width - 2, height: rect.height - 2)
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
        guard let appearanceManager = overlayPanel?.appState?.menuBarManager.appearanceManager else {
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
            trailingEndCap: info.trailingEndCap
        )
    }

    /// Returns a path for the ``MenuBarShapeKind/split`` shape kind.
    private func pathForSplitShape(in rect: CGRect, info: MenuBarSplitShapeInfo, isInset: Bool, screen: NSScreen) -> NSBezierPath {
        guard let appearanceManager = overlayPanel?.appState?.menuBarManager.appearanceManager else {
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
            let items = MenuBarItem.getMenuBarItemsPrivateAPI(for: screen.displayID, onScreenOnly: true)
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
                trailingEndCap: info.trailing.trailingEndCap
            )
        } else {
            let leadingPath = shapePath(
                in: leadingPathBounds,
                leadingEndCap: info.leading.leadingEndCap,
                trailingEndCap: info.leading.trailingEndCap
            )
            let trailingPath = shapePath(
                in: trailingPathBounds,
                leadingEndCap: info.trailing.leadingEndCap,
                trailingEndCap: info.trailing.trailingEndCap
            )
            let path = NSBezierPath()
            path.append(leadingPath)
            path.append(trailingPath)
            return path
        }
    }

    /// Returns the bounds that the view's drawn content can occupy.
    private func getDrawableBounds() -> CGRect {
        return CGRect(
            x: bounds.origin.x,
            y: bounds.origin.y + 5,
            width: bounds.width,
            height: bounds.height - 5
        )
    }

    /// Draws the tint defined by the given configuration in the given rectangle.
    private func drawTint(in rect: CGRect) {
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
    }

    override func draw(_ dirtyRect: NSRect) {
        guard
            let overlayPanel,
            let context = NSGraphicsContext.current
        else {
            return
        }

        let drawableBounds = getDrawableBounds()

        let shapePath = switch configuration.shapeKind {
        case .none:
            NSBezierPath(rect: drawableBounds)
        case .full:
            pathForFullShape(
                in: drawableBounds,
                info: configuration.fullShapeInfo,
                isInset: configuration.isInset,
                screen: overlayPanel.owningScreen
            )
        case .split:
            pathForSplitShape(
                in: drawableBounds,
                info: configuration.splitShapeInfo,
                isInset: configuration.isInset,
                screen: overlayPanel.owningScreen
            )
        }

        var hasBorder = false

        switch configuration.shapeKind {
        case .none:
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

            drawTint(in: drawableBounds)

            if configuration.hasBorder {
                let borderBounds = CGRect(
                    x: bounds.minX,
                    y: bounds.minY + 5,
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

                let borderPath = switch configuration.shapeKind {
                case .none:
                    NSBezierPath(rect: drawableBounds)
                case .full:
                    pathForFullShape(
                        in: drawableBounds,
                        info: configuration.fullShapeInfo,
                        isInset: configuration.isInset,
                        screen: overlayPanel.owningScreen
                    )
                case .split:
                    pathForSplitShape(
                        in: drawableBounds,
                        info: configuration.splitShapeInfo,
                        isInset: configuration.isInset,
                        screen: overlayPanel.owningScreen
                    )
                }

                // HACK: insetting a path to get an "inside" stroke is surprisingly
                // difficult; we can fake the correct line width by doubling it, as
                // anything outside the shape path will be clipped
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
