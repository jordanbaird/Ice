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
        case applicationMenuItemFrames
        case desktopWallpaper

        var description: String { rawValue }
    }

    /// The kind of validation that occurs before an update.
    private enum ValidationKind {
        case showing
        case updates
    }

    /// An error that can occur during an update.
    private enum UpdateError: Error, CustomStringConvertible {
        case applicationMenuItemFrames(any Error)
        case desktopWallpaper(any Error)

        var description: String {
            switch self {
            case .applicationMenuItemFrames(let error):
                "Update of application menu item frames failed: \(error)"
            case .desktopWallpaper(let error):
                "Update of desktop wallpaper failed: \(error)"
            }
        }
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
        func setTask(for flag: UpdateFlag, timeout: Duration, operation: @escaping @Sendable () async throws -> Void) {
            tasks[flag]?.cancel()
            tasks[flag] = Task.detached(timeout: timeout, operation: operation)
        }
    }

    private var cancellables = Set<AnyCancellable>()

    /// Callbacks to perform after the panel is updated.
    ///
    /// - Note: The callbacks are removed after each update.
    private var updateCallbacks = [() -> Void]()

    /// The context that manages panel update tasks.
    private let updateTaskContext = UpdateTaskContext()

    /// The appearance manager that manages the panel.
    private(set) weak var appearanceManager: MenuBarAppearanceManager?

    /// The screen that owns the panel.
    let owningScreen: NSScreen

    /// A Boolean value that indicates whether the panel needs to be shown.
    @Published var needsShow = false

    /// Flags representing the components of the panel currently in need of an update.
    @Published var updateFlags = Set<UpdateFlag>()

    /// A Boolean value that indicates whether the user is dragging a menu bar item.
    @Published var isDraggingMenuBarItem = false

    /// The frames of the application menu's items.
    @Published private(set) var applicationMenuItemFrames = [CGRect]()

    /// The current desktop wallpaper, clipped to the bounds of the menu bar.
    @Published private(set) var desktopWallpaper: CGImage?

    weak var menuBarManager: MenuBarManager? {
        appearanceManager?.menuBarManager
    }

    /// Creates an overlay panel with the given appearance manager and owning screen.
    init(appearanceManager: MenuBarAppearanceManager, owningScreen: NSScreen) {
        self.appearanceManager = appearanceManager
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
            .publisher(for: Notification.Name("AppleInterfaceThemeChangedNotification"))
            .debounce(for: 0.1, scheduler: DispatchQueue.main)
            .sink { [weak self] _ in
                guard let self else {
                    return
                }
                updateTaskContext.setTask(for: .desktopWallpaper, timeout: .seconds(5)) {
                    while true {
                        try Task.checkCancellation()
                        await self.insertUpdateFlag(.desktopWallpaper)
                        try await Task.sleep(for: .seconds(1))
                    }
                }
            }
            .store(in: &c)

        // update the application frames when the menu bar owning app changes
        Publishers.CombineLatest(
            NSWorkspace.shared.publisher(for: \.menuBarOwningApplication),
            NSWorkspace.shared.publisher(for: \.frontmostApplication)
        )
        .sink { [weak self] _ in
            guard
                let self,
                let menuBarManager
            else {
                return
            }
            let displayID = owningScreen.displayID
            updateTaskContext.setTask(for: .applicationMenuItemFrames, timeout: .seconds(10)) {
                var hasUpdated = false
                while true {
                    try Task.checkCancellation()
                    try await Task.sleep(for: .milliseconds(hasUpdated ? 500 : 1))
                    if
                        let latestFrames = try? await menuBarManager.getApplicationMenuItemFrames(for: displayID),
                        await latestFrames != self.applicationMenuItemFrames
                    {
                        await self.insertUpdateFlag(.applicationMenuItemFrames)
                        hasUpdated = true
                    }
                }
            }
        }
        .store(in: &c)

        // make sure the panel switches to the active space
        Timer.publish(every: 2.5, on: .main, in: .default)
            .autoconnect()
            .sink { [weak self] _ in
                guard let self, !isOnActiveSpace else {
                    return
                }
                needsShow = true
            }
            .store(in: &c)

        // continually update the desktop wallpaper; ideally, we would set up
        // an observer for a wallpaper change notification, but macOS doesn't
        // post one anymore; updating every 5 seconds at least keeps the CPU
        // usage around 1-2% on average
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
                guard let owningDisplay = validate(for: .showing) else {
                    return
                }
                do {
                    try show(on: owningDisplay)
                } catch {
                    Logger.overlayPanel.error("Error showing menu bar overlay panel: \(error)")
                }
            }
            .store(in: &c)

        $updateFlags
            .sink { [weak self] flags in
                guard let self, !flags.isEmpty else {
                    return
                }
                defer {
                    updateFlags.removeAll()
                }
                Task {
                    defer {
                        let updateCallbacks = self.updateCallbacks
                        self.updateCallbacks.removeAll()
                        for callback in updateCallbacks {
                            callback()
                        }
                    }
                    guard let owningDisplay = self.validate(for: .updates) else {
                        return
                    }
                    do {
                        try await self.performUpdates(for: flags, display: owningDisplay)
                    } catch {
                        Logger.overlayPanel.error("ERROR: \(error)")
                    }
                }
            }
            .store(in: &c)

        cancellables = c
    }

    /// Inserts the given update flag into the panel's current list of update flags.
    private func insertUpdateFlag(_ flag: UpdateFlag) {
        updateFlags.insert(flag)
    }

    /// Performs validation for the given validation kind. Returns the panel's
    /// owning display if successful. Returns `nil` on failure.
    private func validate(for kind: ValidationKind) -> CGDirectDisplayID? {
        lazy var actionMessage = switch kind {
        case .showing: "Preventing overlay panel from showing."
        case .updates: "Preventing overlay panel from updating."
        }
        let owningDisplay = owningScreen.displayID
        guard let menuBarManager else {
            Logger.overlayPanel.notice("No menu bar manager. \(actionMessage)")
            return nil
        }
        guard !menuBarManager.isFullscreen(for: owningDisplay) else {
            Logger.overlayPanel.notice("Found fullscreen window. \(actionMessage)")
            return nil
        }
        guard AccessibilityMenuBar.hasValidMenuBar(for: owningDisplay) else {
            Logger.overlayPanel.notice("No valid menu bar found. \(actionMessage)")
            return nil
        }
        return owningDisplay
    }

    /// Returns the frame that should be used to show the panel on its owning screen.
    private func getPanelFrame(for display: CGDirectDisplayID) throws -> CGRect {
        let menuBar = try AccessibilityMenuBar(display: display)
        let menuBarFrame = try menuBar.frame()
        return CGRect(
            x: owningScreen.frame.minX,
            y: (owningScreen.frame.maxY - menuBarFrame.height) - 5,
            width: owningScreen.frame.width,
            height: menuBarFrame.height + 5
        )
    }

    /// Stores the frames of the menu bar's application menus.
    private func updateApplicationMenuItemFrames(for display: CGDirectDisplayID) throws {
        guard
            let menuBarManager,
            !menuBarManager.isFullscreen(for: display)
        else {
            applicationMenuItemFrames.removeAll()
            return
        }
        do {
            applicationMenuItemFrames = try menuBarManager.getApplicationMenuItemFrames(for: display)
        } catch {
            applicationMenuItemFrames.removeAll()
            throw error
        }
    }

    /// Stores the area of the desktop wallpaper that is under the menu bar
    /// of the given display.
    private func updateDesktopWallpaper(for display: CGDirectDisplayID) {
        let wallpaper = ScreenCapture.desktopWallpaperBelowMenuBar(for: display)
        if desktopWallpaper?.dataProvider?.data != wallpaper?.dataProvider?.data {
            desktopWallpaper = wallpaper
        }
    }

    /// Updates the panel to prepare for display.
    private func performUpdates(for flags: Set<UpdateFlag>, display: CGDirectDisplayID) async throws {
        try await withThrowingTaskGroup(of: Void.self) { group in
            if flags.contains(.applicationMenuItemFrames) {
                group.addTask {
                    do {
                        try await self.updateApplicationMenuItemFrames(for: display)
                    } catch {
                        throw UpdateError.applicationMenuItemFrames(error)
                    }
                }
            }
            if flags.contains(.desktopWallpaper) {
                group.addTask {
                    await self.updateDesktopWallpaper(for: display)
                }
            }
            try await group.waitForAll()
        }
    }

    /// Shows the panel.
    private func show(on display: CGDirectDisplayID) throws {
        guard
            let appearanceManager,
            let appState = appearanceManager.appState,
            !appState.isPreview
        else {
            return
        }

        guard appearanceManager.overlayPanels.contains(self) else {
            Logger.overlayPanel.notice("Overlay panel \(self) not retained")
            return
        }

        guard
            let menuBarManager,
            !menuBarManager.isFullscreen(for: display)
        else {
            return
        }

        let newFrame = try getPanelFrame(for: display)

        alphaValue = 0
        setFrame(newFrame, display: false)
        orderFrontRegardless()
        updateFlags = [.applicationMenuItemFrames, .desktopWallpaper]
        updateCallbacks.append { [weak self] in
            self?.animator().alphaValue = 1
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

    private weak var menuBarManager: MenuBarManager? {
        overlayPanel?.menuBarManager
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        configureCancellables()
    }

    private func configureCancellables() {
        var c = Set<AnyCancellable>()

        if let overlayPanel {
            overlayPanel.appearanceManager?.$configuration
                .removeDuplicates()
                .assign(to: &$configuration)

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
            // redraw whenever the application menu item frames change
            overlayPanel.$applicationMenuItemFrames
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

        if let menuBarManager {
            for section in menuBarManager.sections {
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
    private func pathForFullShape(in rect: CGRect, info: MenuBarFullShapeInfo) -> NSBezierPath {
        shapePath(
            in: rect,
            leadingEndCap: info.leadingEndCap,
            trailingEndCap: info.trailingEndCap
        )
    }

    /// Returns a path for the ``MenuBarShapeKind/split`` shape kind.
    private func pathForSplitShape(in rect: CGRect, info: MenuBarSplitShapeInfo, display: CGDirectDisplayID) -> NSBezierPath {
        let leadingPathBounds: CGRect = {
            let applicationMenuItemFrames = overlayPanel?.applicationMenuItemFrames ?? []
            var maxX = applicationMenuItemFrames.reduce(into: 0) { maxX, frame in
                maxX += frame.width
            }
            guard maxX != 0 else {
                return .zero
            }
            maxX += 20 // padding so the shape is even on both sides
            return CGRect(x: rect.minX, y: rect.minY, width: maxX, height: rect.height)
        }()
        let trailingPathBounds: CGRect = {
            let items = MenuBarItem.getMenuBarItems(for: display, onScreenOnly: true)
            guard !items.isEmpty else {
                return .zero
            }
            let totalWidth = items.reduce(into: 0) { width, item in
                width += item.frame.width
            }
            var position = rect.maxX - totalWidth
            position -= 7 // padding so the shape is even on both sides
            return CGRect(x: position, y: rect.minY, width: rect.maxX - position, height: rect.height)
        }()

        if leadingPathBounds == .zero || trailingPathBounds == .zero {
            return NSBezierPath(rect: rect)
        } else if leadingPathBounds.intersects(trailingPathBounds) {
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
            let menuBarManager,
            let context = NSGraphicsContext.current
        else {
            return
        }

        let owningDisplay = overlayPanel.owningScreen.displayID

        // FIXME: This check shouldn't be needed. The panel should be ordered out when fullscreen.
        guard !menuBarManager.isFullscreen(for: owningDisplay) else {
            return
        }

        let drawableBounds = getDrawableBounds()

        let shapePath = switch configuration.shapeKind {
        case .none:
            NSBezierPath(rect: drawableBounds)
        case .full:
            pathForFullShape(
                in: drawableBounds,
                info: configuration.fullShapeInfo
            )
        case .split:
            pathForSplitShape(
                in: drawableBounds,
                info: configuration.splitShapeInfo,
                display: owningDisplay
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
                        info: configuration.fullShapeInfo
                    )
                case .split:
                    pathForSplitShape(
                        in: drawableBounds,
                        info: configuration.splitShapeInfo,
                        display: owningDisplay
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
