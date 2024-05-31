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
        case applicationMenuFrames
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
        case applicationMenuFrames(any Error)
        case desktopWallpaper(any Error)

        var description: String {
            switch self {
            case .applicationMenuFrames(let error):
                "Update of application menu frames failed: \(error)"
            case .desktopWallpaper(let error):
                "Update of desktop wallpaper failed: \(error)"
            }
        }
    }

    private var cancellables = Set<AnyCancellable>()

    /// Callbacks to perform after the panel is updated.
    ///
    /// - Note: The callbacks are removed after each update.
    private var updateCallbacks = [() -> Void]()

    /// The keyed times of the last successful updates.
    private var lastSuccessfulUpdateTimes = [UpdateFlag: Date]()

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

    /// The frames of the menu bar's application menus.
    @Published private(set) var applicationMenuFrames = [CGRect]()

    /// The current desktop wallpaper, clipped to the bounds of the menu bar.
    @Published private(set) var desktopWallpaper: CGImage?

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
                Task {
                    let startTime = Date.now
                    while Date.now < startTime + 5 {
                        self.updateFlags.insert(.desktopWallpaper)
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
            guard let self else {
                return
            }
            let initialFrames = applicationMenuFrames
            let displayID = owningScreen.displayID
            Task.detached(timeout: .seconds(1)) {
                try await Task.sleep(for: .milliseconds(10))
                while true {
                    try Task.checkCancellation()
                    try await Task.sleep(for: .milliseconds(1))
                    if
                        let latestFrames = try? await self.getApplicationMenuFrames(for: displayID),
                        latestFrames != initialFrames
                    {
                        await MainActor.run {
                            _ = self.updateFlags.insert(.applicationMenuFrames)
                        }
                        break
                    }
                }
            }
        }
        .store(in: &c)

        // perform updates as follows:
        //
        //  - application frames after 10 seconds without an update
        //  - desktop wallpaper after 5 seconds without an update
        //
        // this ensures that cases we haven't covered are eventually handled, such
        // as wallpaper changes, which can't be reliably observed in Sonoma
        Timer.publish(every: 1, on: .main, in: .default)
            .autoconnect()
            .sink { [weak self] _ in
                guard let self else {
                    return
                }
                insertUpdateFlagIfNeeded(.applicationMenuFrames, interval: 10)
                insertUpdateFlagIfNeeded(.desktopWallpaper, interval: 5)
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

    /// Inserts the given update flag if the given time interval has passed
    /// since the last successful update.
    private func insertUpdateFlagIfNeeded(_ flag: UpdateFlag, interval: TimeInterval) {
        guard
            let time = lastSuccessfulUpdateTimes[flag],
            Date.now.timeIntervalSince(time) >= interval
        else {
            return
        }
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
        guard let menuBarManager = appearanceManager?.menuBarManager else {
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

    /// Returns the current application menu frames for the given display.
    private func getApplicationMenuFrames(for display: CGDirectDisplayID) throws -> [CGRect] {
        let menuBar = try AccessibilityMenuBar(display: display)
        return try menuBar.menuBarItems().map { try $0.frame() }
    }

    /// Stores the frames of the menu bar's application menus.
    private func updateApplicationMenuFrames(for display: CGDirectDisplayID) throws {
        do {
            if
                let menuBarManager = appearanceManager?.menuBarManager,
                menuBarManager.isFullscreen(for: display)
            {
                applicationMenuFrames.removeAll()
            } else {
                applicationMenuFrames = try getApplicationMenuFrames(for: display)
            }
            lastSuccessfulUpdateTimes[.applicationMenuFrames] = .now
        } catch {
            applicationMenuFrames.removeAll()
            throw error
        }
    }

    /// Stores the area of the desktop wallpaper that is under the menu bar
    /// of the given display.
    private func updateDesktopWallpaper(for display: CGDirectDisplayID) async throws {
        do {
            desktopWallpaper = try await ScreenCapture.desktopWallpaperBelowMenuBar(for: display, timeout: .seconds(1))
            lastSuccessfulUpdateTimes[.desktopWallpaper] = .now
        } catch {
            desktopWallpaper = nil
            throw error
        }
    }

    /// Updates the panel to prepare for display.
    private func performUpdates(for flags: Set<UpdateFlag>, display: CGDirectDisplayID) async throws {
        try await withThrowingTaskGroup(of: Void.self) { group in
            if flags.contains(.applicationMenuFrames) {
                group.addTask {
                    do {
                        try await self.updateApplicationMenuFrames(for: display)
                    } catch {
                        throw UpdateError.applicationMenuFrames(error)
                    }
                }
            }
            if flags.contains(.desktopWallpaper) {
                group.addTask {
                    do {
                        try await self.updateDesktopWallpaper(for: display)
                    } catch {
                        throw UpdateError.desktopWallpaper(error)
                    }
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
            let menuBarManager = appearanceManager.menuBarManager,
            !menuBarManager.isFullscreen(for: display)
        else {
            return
        }

        let newFrame = try getPanelFrame(for: display)

        alphaValue = 0
        setFrame(newFrame, display: false)
        orderFrontRegardless()
        updateFlags = [.applicationMenuFrames, .desktopWallpaper]
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

    /// The overlay panel that contains the content view.
    private var overlayPanel: MenuBarOverlayPanel? {
        window as? MenuBarOverlayPanel
    }

    /// The appearance manager that manages the content view's panel.
    private var appearanceManager: MenuBarAppearanceManager? {
        overlayPanel?.appearanceManager
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        configureCancellables()
    }

    private func configureCancellables() {
        var c = Set<AnyCancellable>()

        if let overlayPanel {
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
            // redraw whenever the application menu frames change
            overlayPanel.$applicationMenuFrames
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

        if let appearanceManager {
            // redraw whenever the manager's parameters change
            appearanceManager.$configuration
                .receive(on: DispatchQueue.main)
                .sink { [weak self] _ in
                    self?.needsDisplay = true
                }
                .store(in: &c)
        }

        if let menuBarManager = appearanceManager?.menuBarManager {
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
            let applicationMenuFrames = overlayPanel?.applicationMenuFrames ?? []
            var maxX = applicationMenuFrames.reduce(into: 0) { maxX, frame in
                maxX += frame.width
            }
            guard maxX != 0 else {
                return .zero
            }
            maxX += 20 // padding so the shape is even on both sides
            return CGRect(x: rect.minX, y: rect.minY, width: maxX, height: rect.height)
        }()
        let trailingPathBounds: CGRect = {
            guard
                let itemManager = appearanceManager?.menuBarManager?.itemManager,
                let items = try? itemManager.getMenuBarItems(for: display, onScreenOnly: true)
            else {
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
    private func drawTint(in rect: CGRect, configuration: MenuBarAppearanceConfiguration) {
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
            let appearanceManager,
            let menuBarManager = appearanceManager.menuBarManager,
            let context = NSGraphicsContext.current
        else {
            return
        }

        let owningDisplay = overlayPanel.owningScreen.displayID

        guard !menuBarManager.isFullscreen(for: owningDisplay) else {
            return
        }

        let configuration = appearanceManager.configuration
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

            drawTint(in: drawableBounds, configuration: configuration)

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

                drawTint(in: drawableBounds, configuration: configuration)
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
