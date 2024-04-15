//
//  MenuBarOverlayPanel.swift
//  Ice
//

import AXSwift
import Cocoa
import Combine
import OSLog

// MARK: - MenuBarOverlayPanel

/// A subclass of `NSPanel` that sits atop the menu bar to alter its appearance.
class MenuBarOverlayPanel: NSPanel {
    enum UpdateError: Error, CustomStringConvertible {
        case applicationMenuFrame(any Error)
        case desktopWallpaper(any Error)

        var description: String {
            switch self {
            case .applicationMenuFrame(let error):
                "Application menu frame update failed: \(error)"
            case .desktopWallpaper(let error):
                "Desktop wallpaper update failed: \(error)"
            }
        }
    }

    private var cancellables = Set<AnyCancellable>()

    /// The appearance manager that manages the panel.
    private(set) weak var appearanceManager: MenuBarAppearanceManager?

    /// The screen capture manager for the panel.
    let screenCaptureManager: ScreenCaptureManager

    /// The screen that owns the panel.
    let owningScreen: NSScreen

    /// A Boolean value that indicates whether the panel needs to be shown.
    @Published var needsShow = false

    /// A Boolean value that indicates whether the panel needs to be updated.
    @Published var needsUpdate = true

    /// A Boolean value that indicates whether the user is dragging a menu bar item.
    @Published var isDraggingMenuBarItem = false

    /// The frames of the menu bar's application menus.
    @Published private(set) var applicationMenuFrames = [CGRect]()

    /// The current desktop wallpaper, clipped to the bounds of the menu bar.
    @Published private(set) var desktopWallpaper: CGImage?

    /// Creates an overlay panel with the given appearance manager, screen capture
    /// manager, and owning display.
    init(
        appearanceManager: MenuBarAppearanceManager,
        screenCaptureManager: ScreenCaptureManager,
        owningScreen: NSScreen
    ) {
        self.appearanceManager = appearanceManager
        self.screenCaptureManager = screenCaptureManager
        self.owningScreen = owningScreen
        super.init(
            contentRect: .zero,
            styleMask: [.borderless, .fullSizeContentView, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        self.level = .statusBar
        self.title = String(describing: Self.self)
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
            .debounce(for: 1, scheduler: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.needsUpdate = true
            }
            .store(in: &c)

        // update when frontmost application changes, or when it owns the menu bar
        Publishers.CombineLatest3(
            NSWorkspace.shared.publisher(for: \.frontmostApplication),
            NSWorkspace.shared.publisher(for: \.frontmostApplication?.isFinishedLaunching),
            NSWorkspace.shared.publisher(for: \.frontmostApplication?.ownsMenuBar)
        )
        .debounce(for: 0.1, scheduler: DispatchQueue.main)
        .sink { [weak self] _ in
            self?.needsUpdate = true
        }
        .store(in: &c)

        // fallback
        Timer.publish(every: 5, on: .main, in: .default)
            .autoconnect()
            .sink { [weak self] _ in
                self?.needsUpdate = true
            }
            .store(in: &c)

        // fallback
        Timer.publish(every: 2.5, on: .main, in: .default)
            .autoconnect()
            .sink { [weak self] _ in
                guard
                    let self,
                    !isOnActiveSpace
                else {
                    return
                }
                needsShow = true
            }
            .store(in: &c)

        $needsShow
            .removeDuplicates()
            .sink { [weak self] needsShow in
                guard
                    let self,
                    needsShow
                else {
                    return
                }
                defer {
                    self.needsShow = false
                }
                Task {
                    do {
                        try await self.show()
                    } catch {
                        Logger.overlayPanel.error("Error showing menu bar overlay panel: \(error)")
                    }
                }
            }
            .store(in: &c)

        $needsUpdate
            .removeDuplicates()
            .sink { [weak self] needsUpdate in
                guard
                    let self,
                    needsUpdate
                else {
                    return
                }
                defer {
                    self.needsUpdate = false
                }
                Task {
                    do {
                        guard let owningDisplay = DisplayInfo(nsScreen: self.owningScreen) else {
                            Logger.overlayPanel.notice("No owning display. Preventing panel update.")
                            return
                        }
                        if let menuBarManager = self.appearanceManager?.menuBarManager {
                            guard try await !menuBarManager.isFullscreen(for: owningDisplay) else {
                                Logger.overlayPanel.notice("Found fullscreen window. Preventing panel update.")
                                return
                            }
                        }
                        guard await AccessibilityMenuBar.hasValidMenuBar(for: owningDisplay) else {
                            Logger.overlayPanel.notice("No valid menu bar found. Preventing panel update.")
                            return
                        }
                        try await self.performUpdates()
                    } catch {
                        Logger.overlayPanel.error("ERROR: \(error)")
                    }
                }
            }
            .store(in: &c)

        cancellables = c
    }

    /// Returns the frame that should be used to show the panel on its owning screen.
    private func getFrame(for display: DisplayInfo) async throws -> CGRect {
        let menuBar = try await AccessibilityMenuBar(display: display)
        let menuBarFrame: CGRect = try menuBar.frame()
        return CGRect(
            x: owningScreen.frame.minX,
            y: (owningScreen.frame.maxY - menuBarFrame.height) - 5,
            width: owningScreen.frame.width,
            height: menuBarFrame.height + 5
        )
    }

    /// Stores the frames of the menu bar's application menus.
    private func updateApplicationMenuFrames() async throws {
        do {
            guard let owningDisplay = DisplayInfo(nsScreen: owningScreen) else {
                throw DisplayInfo.DisplayError.cannotComplete
            }
            if
                let menuBarManager = appearanceManager?.menuBarManager,
                try await menuBarManager.isFullscreen(for: owningDisplay)
            {
                applicationMenuFrames.removeAll()
            } else {
                let menuBar = try await AccessibilityMenuBar(display: owningDisplay)
                let items = try menuBar.menuBarItems()
                applicationMenuFrames = try items.map { item in
                    try item.frame()
                }
            }
        } catch {
            applicationMenuFrames.removeAll()
            throw error
        }
    }

    /// Stores the area of the desktop wallpaper that is under the menu bar
    /// of the given display.
    private func updateDesktopWallpaper() async throws {
        do {
            guard let owningDisplay = DisplayInfo(nsScreen: owningScreen) else {
                throw DisplayInfo.DisplayError.cannotComplete
            }
            desktopWallpaper = try await screenCaptureManager.desktopWallpaperBelowMenuBar(for: owningDisplay)
        } catch {
            desktopWallpaper = nil
            throw error
        }
    }

    /// Updates the panel to prepare for display.
    private func performUpdates() async throws {
        let applicationMenuFramesTask = Task.detached {
            do {
                try await self.updateApplicationMenuFrames()
            } catch {
                throw UpdateError.applicationMenuFrame(error)
            }
        }
        let desktopWallpaperTask = Task.detached {
            do {
                try await self.updateDesktopWallpaper()
            } catch {
                throw UpdateError.desktopWallpaper(error)
            }
        }
        try await applicationMenuFramesTask.value
        try await desktopWallpaperTask.value
    }

    /// Returns the combined application menu frame, that is, the result of performing
    /// the `union` operation on every element in the ``applicationMenuFrames`` array.
    func getCombinedApplicationMenuFrame() -> CGRect {
        return applicationMenuFrames.reduce(into: .zero) { result, frame in
            result = result.union(frame)
        }
    }

    /// Shows the panel.
    func show() async throws {
        guard !AppState.shared.isPreview else {
            return
        }

        guard let owningDisplay = DisplayInfo(nsScreen: owningScreen) else {
            throw DisplayInfo.DisplayError.cannotComplete
        }

        guard
            let appearanceManager,
            let menuBarManager = appearanceManager.menuBarManager,
            try await !menuBarManager.isFullscreen(for: owningDisplay)
        else {
            return
        }

        let displayFrame = try await getFrame(for: owningDisplay)

        // only continue if the appearance manager holds a reference to this panel
        guard appearanceManager.overlayPanels.contains(self) else {
            Logger.overlayPanel.notice("Overlay panel \(self) not retained")
            return
        }

        alphaValue = 0
        setFrame(displayFrame, display: true)
        orderFrontRegardless()
        needsUpdate = true
        try await Task.sleep(for: .seconds(0.1))
        animator().alphaValue = 1
    }

    /// Hides the panel.
    func hide() {
        close()
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
            // redraw when the application menus are hidden
            menuBarManager.$isHidingApplicationMenus
                .sink { [weak self] _ in
                    self?.needsDisplay = true
                }
                .store(in: &c)

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

    private func shapePath(
        in rect: CGRect,
        leadingEndCap: MenuBarEndCap,
        trailingEndCap: MenuBarEndCap,
        insetX: CGFloat,
        insetY: CGFloat
    ) -> NSBezierPath {
        let insetRect = rect.insetBy(dx: insetX, dy: insetY)
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
    private func pathForFullShape(
        in rect: CGRect,
        info: MenuBarFullShapeInfo,
        insetX: CGFloat,
        insetY: CGFloat
    ) -> NSBezierPath {
        return shapePath(
            in: rect,
            leadingEndCap: info.leadingEndCap,
            trailingEndCap: info.trailingEndCap,
            insetX: insetX,
            insetY: insetY
        )
    }

    /// Returns a path for the ``MenuBarShapeKind/split`` shape kind.
    private func pathForSplitShape(
        in rect: CGRect,
        info: MenuBarSplitShapeInfo,
        display: DisplayInfo,
        insetX: CGFloat,
        insetY: CGFloat
    ) -> NSBezierPath {
        let leadingPathBounds: CGRect = {
            var maxX: CGFloat = 0
            if
                let menuBarManager = appearanceManager?.menuBarManager,
                menuBarManager.isHidingApplicationMenus,
                let overlayPanel,
                overlayPanel.owningScreen.displayID == CGMainDisplayID(),
                let appleMenuMaxX = overlayPanel.applicationMenuFrames.first?.width
            {
                // special case to prevent the leading path from jittering when hiding the
                // application menus; this technically changes the shape just _before_ the
                // menus hide, but it looks the best
                maxX = appleMenuMaxX
            } else if let overlayPanel {
                maxX = overlayPanel.applicationMenuFrames.reduce(into: 0) { $0 += $1.width }
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
                trailingEndCap: info.trailing.trailingEndCap,
                insetX: insetX,
                insetY: insetY
            )
        } else {
            let leadingPath = shapePath(
                in: leadingPathBounds,
                leadingEndCap: info.leading.leadingEndCap,
                trailingEndCap: info.leading.trailingEndCap,
                insetX: insetX,
                insetY: insetY
            )
            let trailingPath = shapePath(
                in: trailingPathBounds,
                leadingEndCap: info.trailing.leadingEndCap,
                trailingEndCap: info.trailing.trailingEndCap,
                insetX: insetX,
                insetY: insetY
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
            let context = NSGraphicsContext.current,
            let owningDisplay = DisplayInfo(nsScreen: overlayPanel.owningScreen)
        else {
            return
        }

        do {
            if try menuBarManager.isFullscreen(for: owningDisplay) {
                return
            }
        } catch {
            Logger.overlayPanel.error("ERROR: \(error)")
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
                info: configuration.fullShapeInfo,
                insetX: 2,
                insetY: 1
            )
        case .split:
            pathForSplitShape(
                in: drawableBounds,
                info: configuration.splitShapeInfo,
                display: owningDisplay,
                insetX: 2,
                insetY: 1
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
                        info: configuration.fullShapeInfo,
                        insetX: 1,
                        insetY: 0
                    )
                case .split:
                    pathForSplitShape(
                        in: drawableBounds,
                        info: configuration.splitShapeInfo,
                        display: owningDisplay,
                        insetX: 1,
                        insetY: 0
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
