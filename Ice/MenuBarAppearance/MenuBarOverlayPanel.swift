//
//  MenuBarOverlayPanel.swift
//  Ice
//

import AXSwift
import Cocoa
import Combine
import OSLog
import ScreenCaptureKit

// MARK: - MenuBarOverlayPanel

/// A subclass of `NSPanel` that sits atop the menu bar
/// to alter its appearance.
class MenuBarOverlayPanel: NSPanel {
    private var cancellables = Set<AnyCancellable>()

    /// The appearance manager that manages the panel.
    private(set) weak var appearanceManager: MenuBarAppearanceManager?

    private let screenCaptureManager = ScreenCaptureManager.shared

    /// The screen that owns the panel.
    let owningScreen: NSScreen

    /// A Boolean value that indicates whether the panel
    /// needs to be updated.
    @Published var needsUpdate = true

    /// A Boolean value that indicates whether the user
    /// is dragging a menu bar item.
    @Published var isDraggingMenuBarItem = false

    /// The menu bar associated with the panel.
    @Published private(set) var menuBar: UIElement?

    /// The max X position of the main menu.
    @Published private(set) var mainMenuMaxX: CGFloat?

    /// The current desktop wallpaper, clipped to the bounds
    /// of the menu bar.
    @Published private(set) var desktopWallpaper: CGImage?

    /// The frame that should be used to display the panel.
    private var frameForDisplay: CGRect? {
        guard let menuBarFrame: CGRect = try? menuBar?.attribute(.frame) else {
            return nil
        }
        return CGRect(
            x: owningScreen.frame.origin.x,
            y: (owningScreen.frame.maxY - menuBarFrame.height) - 5,
            width: owningScreen.frame.width,
            height: menuBarFrame.height + 5
        )
    }

    /// Creates an overlay panel with the given appearance
    /// manager and owning screen.
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
            .delay(for: 0.1, scheduler: DispatchQueue.main)
            .sink { [weak self] _ in
                guard
                    let self,
                    let appearanceManager,
                    let menuBarManager = appearanceManager.menuBarManager
                else {
                    return
                }
                if !menuBarManager.isMenuBarHidden(for: owningScreen) && !isOnActiveSpace {
                    show()
                }
            }
            .store(in: &c)

        // update when light/dark mode changes
        DistributedNotificationCenter.default()
            .publisher(for: Notification.Name("AppleInterfaceThemeChangedNotification"))
            .delay(for: 0.1, scheduler: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.needsUpdate = true
            }
            .store(in: &c)

        // update when active space changes
        NSWorkspace.shared.notificationCenter
            .publisher(for: NSWorkspace.activeSpaceDidChangeNotification)
            .delay(for: 0.1, scheduler: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.needsUpdate = true
            }
            .store(in: &c)

        // update when frontmost application changes,
        // or when it owns the menu bar
        Publishers.CombineLatest(
            NSWorkspace.shared.publisher(for: \.frontmostApplication),
            NSWorkspace.shared.publisher(for: \.frontmostApplication?.ownsMenuBar)
        )
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
                screenCaptureManager.updateWithCompletionHandler {
                    DispatchQueue.main.async {
                        self.updateDesktopWallpaper()
                        self.updateMenuBar()
                    }
                }
            }
            .store(in: &c)

        $menuBar
            .sink { [weak self] menuBar in
                self?.updateMainMenuMaxX(menuBar: menuBar)
            }
            .store(in: &c)

        cancellables = c
    }

    /// Stores the area of the desktop wallpaper that is
    /// under the menu bar.
    private func updateDesktopWallpaper() {
        Task {
            do {
                guard
                    let owningDisplay = DisplayInfo(displayID: owningScreen.displayID),
                    let wallpaper = try await screenCaptureManager.desktopWallpaperBelowMenuBar(for: owningDisplay)
                else {
                    return
                }
                desktopWallpaper = wallpaper
            } catch {
                Logger.overlayPanel.error("Error updating desktop wallpaper: \(error)")
            }
        }
    }

    /// Stores a reference to the menu bar using the given
    /// menu bar window.
    private func updateMenuBar() {
        guard
            let owningDisplay = DisplayInfo(displayID: owningScreen.displayID),
            let menuBarWindow = screenCaptureManager.menuBarWindow(for: owningDisplay)
        else {
            return
        }
        do {
            guard
                let menuBar = try systemWideElement.elementAtPosition(
                    Float(menuBarWindow.frame.origin.x),
                    Float(menuBarWindow.frame.origin.y)
                ),
                try menuBar.role() == .menuBar
            else {
                self.menuBar = nil
                return
            }
            self.menuBar = menuBar
        } catch {
            Logger.overlayPanel.error("Error updating menu bar: \(error)")
        }
    }

    /// Stores the maxX position of the menu bar.
    private func updateMainMenuMaxX(menuBar: UIElement?) {
        guard let menuBar else {
            return
        }
        do {
            guard let children: [UIElement] = try menuBar.arrayAttribute(.children) else {
                mainMenuMaxX = nil
                return
            }
            mainMenuMaxX = try children.reduce(into: 0) { result, child in
                if let frame: CGRect = try child.attribute(.frame) {
                    result += frame.width
                }
            }
        } catch {
            Logger.overlayPanel.error("Error updating main menu maxX: \(error)")
        }
    }

    /// Shows the panel.
    func show() {
        guard !AppState.shared.isPreview else {
            return
        }

        guard let frameForDisplay else {
            Logger.overlayPanel.notice("Missing frame for display")
            return
        }

        // only continue if the appearance manager holds
        // a reference to this panel
        guard
            let appearanceManager,
            appearanceManager.overlayPanels.contains(self)
        else {
            Logger.overlayPanel.notice("Overlay panel \(self) not retained")
            return
        }

        alphaValue = 0
        setFrame(frameForDisplay, display: true)
        orderFrontRegardless()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            self.animator().alphaValue = 1
        }
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

    /// The bounds that the view's drawn content can occupy.
    var drawableBounds: CGRect {
        CGRect(
            x: bounds.origin.x,
            y: bounds.origin.y + 5,
            width: bounds.width,
            height: bounds.height - 5
        )
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
            // redraw whenever the main menu maxX changes
            overlayPanel.$mainMenuMaxX
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
                // redraw whenever the window frame of a section's control
                // item changes
                //
                // - NOTE: A previous attempt was made to redraw the view when the
                //   section's `isHidden` property was changed. This would be
                //   semantically ideal, but the property sometimes changes before
                //   the menu bar items are actually updated on-screen. Since the
                //   view's drawing process relies on getting an accurate position
                //   of each menu bar item, we need to use something that publishes
                //   its changes only after the items are updated.
                section.controlItem.$windowFrame
                    .receive(on: DispatchQueue.main)
                    .sink { [weak self] _ in
                        self?.needsDisplay = true
                    }
                    .store(in: &c)

                // redraw whenever the visibility of a section's control item changes
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

    /// Returns a path for the ``MenuBarShapeKind/full`` shape kind.
    private func pathForFullShapeKind(in rect: CGRect, info: MenuBarFullShapeInfo) -> NSBezierPath {
        let shapeBounds = CGRect(
            x: rect.height / 2,
            y: rect.origin.y,
            width: rect.width - rect.height,
            height: rect.height
        )
        let leadingEndCapBounds = CGRect(
            x: rect.origin.x,
            y: rect.origin.y,
            width: rect.height,
            height: rect.height
        )
        let trailingEndCapBounds = CGRect(
            x: rect.width - rect.height,
            y: rect.origin.y,
            width: rect.height,
            height: rect.height
        )

        var path = NSBezierPath(rect: shapeBounds)

        path = switch info.leadingEndCap {
        case .square: path.union(NSBezierPath(rect: leadingEndCapBounds))
        case .round: path.union(NSBezierPath(ovalIn: leadingEndCapBounds))
        }

        path = switch info.trailingEndCap {
        case .square: path.union(NSBezierPath(rect: trailingEndCapBounds))
        case .round: path.union(NSBezierPath(ovalIn: trailingEndCapBounds))
        }

        return path
    }

    /// Returns a path for the ``MenuBarShapeKind/split`` shape kind.
    private func pathForSplitShapeKind(in rect: CGRect, info: MenuBarSplitShapeInfo) -> NSBezierPath {
        guard
            let menuBarManager = overlayPanel?.appearanceManager?.menuBarManager,
            let mainMenuMaxX = overlayPanel?.mainMenuMaxX
        else {
            return NSBezierPath(rect: rect)
        }

        let padding: CGFloat = 8

        let leadingPath: NSBezierPath = {
            let shapeBounds = CGRect(
                x: rect.height / 2,
                y: rect.origin.y,
                width: (mainMenuMaxX - (rect.height / 2)) + padding,
                height: rect.height
            )
            let leadingEndCapBounds = CGRect(
                x: rect.origin.x,
                y: rect.origin.y,
                width: rect.height,
                height: rect.height
            )
            let trailingEndCapBounds = CGRect(
                x: (mainMenuMaxX - (rect.height / 2)) + padding,
                y: rect.origin.y,
                width: rect.height,
                height: rect.height
            )

            var path = NSBezierPath(rect: shapeBounds)

            path = switch info.leading.leadingEndCap {
            case .square: path.union(NSBezierPath(rect: leadingEndCapBounds))
            case .round: path.union(NSBezierPath(ovalIn: leadingEndCapBounds))
            }

            path = switch info.leading.trailingEndCap {
            case .square: path.union(NSBezierPath(rect: trailingEndCapBounds))
            case .round: path.union(NSBezierPath(ovalIn: trailingEndCapBounds))
            }

            return path
        }()

        let trailingPath: NSBezierPath = {
            guard
                let overlayPanel,
                let owningDisplay = DisplayInfo(displayID: overlayPanel.owningScreen.displayID)
            else {
                return NSBezierPath(rect: rect)
            }

            let items = menuBarManager.itemManager.getMenuBarItems(for: owningDisplay, onScreenOnly: true)
            let totalWidth = items.reduce(into: 0) { width, item in
                width += item.frame.width
            }
            let position = rect.maxX - totalWidth - padding

            let shapeBounds = CGRect(
                x: position + (rect.height / 2),
                y: rect.origin.y,
                width: rect.maxX - (position + rect.height),
                height: rect.height
            )
            let leadingEndCapBounds = CGRect(
                x: position,
                y: rect.origin.y,
                width: rect.height,
                height: rect.height
            )
            let trailingEndCapBounds = CGRect(
                x: rect.maxX - rect.height,
                y: rect.origin.y,
                width: rect.height,
                height: rect.height
            )

            var path = NSBezierPath(rect: shapeBounds)

            path = switch info.trailing.leadingEndCap {
            case .square: path.union(NSBezierPath(rect: leadingEndCapBounds))
            case .round: path.union(NSBezierPath(ovalIn: leadingEndCapBounds))
            }

            path = switch info.trailing.trailingEndCap {
            case .square: path.union(NSBezierPath(rect: trailingEndCapBounds))
            case .round: path.union(NSBezierPath(ovalIn: trailingEndCapBounds))
            }

            return path
        }()

        if leadingPath.intersects(trailingPath) {
            let info = MenuBarFullShapeInfo(
                leadingEndCap: info.leading.leadingEndCap,
                trailingEndCap: info.trailing.trailingEndCap
            )
            return pathForFullShapeKind(in: rect, info: info)
        } else {
            let path = NSBezierPath()
            path.append(leadingPath)
            path.append(trailingPath)
            return path
        }
    }

    private func drawTint(configuration: MenuBarAppearanceConfiguration) {
        switch configuration.tintKind {
        case .none:
            break
        case .solid:
            if let tintColor = NSColor(cgColor: configuration.tintColor)?.withAlphaComponent(0.2) {
                tintColor.setFill()
                NSBezierPath(rect: drawableBounds).fill()
            }
        case .gradient:
            if let tintGradient = configuration.tintGradient.withAlphaComponent(0.2).nsGradient {
                tintGradient.draw(in: drawableBounds, angle: 0)
            }
        }
    }

    override func draw(_ dirtyRect: NSRect) {
        guard
            let overlayPanel,
            let appearanceManager = overlayPanel.appearanceManager,
            let menuBarManager = appearanceManager.menuBarManager,
            let context = NSGraphicsContext.current
        else {
            return
        }

        context.saveGraphicsState()
        defer {
            context.restoreGraphicsState()
        }

        if menuBarManager.isMenuBarHidden(for: overlayPanel.owningScreen) {
            return
        }

        let configuration = appearanceManager.configuration

        let shapePath = switch configuration.shapeKind {
        case .none:
            NSBezierPath(rect: drawableBounds)
        case .full:
            pathForFullShapeKind(in: drawableBounds, info: configuration.fullShapeInfo)
        case .split:
            pathForSplitShapeKind(in: drawableBounds, info: configuration.splitShapeInfo)
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

            drawTint(configuration: configuration)

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

            shapePath.setClip()

            drawTint(configuration: configuration)

            if
                hasBorder,
                let borderColor = NSColor(cgColor: configuration.borderColor)
            {
                // swiftlint:disable:next force_cast
                let borderPath = shapePath.copy() as! NSBezierPath
                // HACK: insetting a path to get an "inside" stroke is surprisingly
                // difficult; we can fake the correct line width by doubling it, as
                // anything outside the shape path will be clipped
                borderPath.lineWidth = configuration.borderWidth * 2
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
