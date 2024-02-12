//
//  MenuBarAppearancePanel.swift
//  Ice
//

import AXSwift
import Cocoa
import Combine
import OSLog
import ScreenCaptureKit

// MARK: - MenuBarAppearancePanel

/// A subclass of `NSPanel` that sits atop or underneath
/// the menu bar to alter its appearance.
class MenuBarAppearancePanel: NSPanel {
    private var cancellables = Set<AnyCancellable>()

    /// The appearance manager that manages the panel.
    private(set) weak var appearanceManager: MenuBarAppearanceManager?

    /// The screen that owns the panel.
    let owningScreen: NSScreen

    /// A Boolean value that indicates whether the screen
    /// is currently locked.
    private var screenIsLocked = false

    /// A Boolean value that indicates whether the screen
    /// saver is currently active.
    private var screenSaverIsActive = false

    /// The menu bar associated with the panel.
    @Published private(set) var menuBar: UIElement?

    /// The current desktop wallpaper, clipped to the bounds
    /// of the menu bar.
    @Published private(set) var desktopWallpaper: CGImage?

    /// Creates an appearance panel with the given appearance
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
        self.contentView = MenuBarAppearancePanelContentView(appearancePanel: self)
        configureCancellables()
    }

    private func configureCancellables() {
        var c = Set<AnyCancellable>()

        DistributedNotificationCenter.default()
            .publisher(for: Notification.Name("com.apple.screenIsLocked"))
            .sink { [weak self] _ in
                self?.screenIsLocked = true
            }
            .store(in: &c)

        DistributedNotificationCenter.default()
            .publisher(for: Notification.Name("com.apple.screenIsUnlocked"))
            .sink { [weak self] _ in
                self?.screenIsLocked = false
            }
            .store(in: &c)

        DistributedNotificationCenter.default()
            .publisher(for: Notification.Name("com.apple.screensaver.didstart"))
            .sink { [weak self] _ in
                self?.screenSaverIsActive = true
            }
            .store(in: &c)

        DistributedNotificationCenter.default()
            .publisher(for: Notification.Name("com.apple.screensaver.didstop"))
            .sink { [weak self] _ in
                self?.screenSaverIsActive = false
            }
            .store(in: &c)

        // always show the panel on the active space
        NSWorkspace.shared.notificationCenter
            .publisher(for: NSWorkspace.activeSpaceDidChangeNotification)
            .delay(for: 0.1, scheduler: DispatchQueue.main)
            .sink { [weak self] _ in
                guard let self else {
                    return
                }

                // if the screen's visible frame and frame are the same,
                // the menu bar is hidden; do not allow the panel to show
                let canShow = owningScreen.visibleFrame != owningScreen.frame

                if canShow && !isOnActiveSpace {
                    show()
                }
            }
            .store(in: &c)

        ScreenCaptureManager.shared.$windows
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                guard
                    let self,
                    let owningDisplay = getOwningDisplay(),
                    let wallpaperWindow = getWallpaperWindow(owningDisplay: owningDisplay),
                    let menuBarWindow = getMenuBarWindow(owningDisplay: owningDisplay)
                else {
                    return
                }
                updateDesktopWallpaper(
                    owningDisplay: owningDisplay,
                    wallpaperWindow: wallpaperWindow,
                    menuBarWindow: menuBarWindow
                )
                updateMenuBar(menuBarWindow: menuBarWindow)
            }
            .store(in: &c)

        cancellables = c
    }

    /// Returns the `SCDisplay` equivalent of the owning screen.
    private func getOwningDisplay() -> SCDisplay? {
        ScreenCaptureManager.shared.displays.first { display in
            display.displayID == owningScreen.displayID
        }
    }

    private func getWallpaperWindow(owningDisplay: SCDisplay) -> SCWindow? {
        ScreenCaptureManager.shared.windows.first { window in
            // wallpaper window belongs to the Dock process
            window.owningApplication?.bundleIdentifier == "com.apple.dock" &&
            window.isOnScreen &&
            window.title?.hasPrefix("Wallpaper-") == true &&
            owningDisplay.frame.contains(window.frame)
        }
    }

    private func getMenuBarWindow(owningDisplay: SCDisplay) -> SCWindow? {
        ScreenCaptureManager.shared.windows.first { window in
            // menu bar window belongs to the WindowServer process
            // (identified by an empty string)
            window.owningApplication?.bundleIdentifier == "" &&
            window.windowLayer == kCGMainMenuWindowLevel &&
            window.title == "Menubar" &&
            owningDisplay.frame.contains(window.frame)
        }
    }

    private func updateDesktopWallpaper(
        owningDisplay: SCDisplay,
        wallpaperWindow: SCWindow,
        menuBarWindow: SCWindow
    ) {
        guard !screenIsLocked else {
            Logger.appearancePanel.debug("Screen is locked")
            return
        }

        guard !screenSaverIsActive else {
            Logger.appearancePanel.debug("Screen saver is active")
            return
        }

        Task { @MainActor in
            do {
                desktopWallpaper = try await ScreenshotManager.captureImage(
                    withTimeout: .milliseconds(500),
                    window: wallpaperWindow,
                    display: owningDisplay,
                    captureRect: CGRect(origin: .zero, size: menuBarWindow.frame.size),
                    options: .ignoreFraming
                )
            } catch {
                Logger.appearancePanel.error("Error updating desktop wallpaper: \(error)")
            }
        }
    }

    private func updateMenuBar(menuBarWindow: SCWindow) {
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
            Logger.appearancePanel.error("Error updating menu bar: \(error)")
        }
    }

    /// Shows the panel.
    func show() {
        guard !AppState.shared.isPreview else {
            return
        }
        do {
            guard let menuBarFrame: CGRect = try menuBar?.attribute(.frame) else {
                Logger.appearancePanel.error("Missing menu bar frame")
                return
            }
            alphaValue = 0
            let adjustedFrame = CGRect(
                x: owningScreen.frame.origin.x,
                y: (owningScreen.frame.maxY - menuBarFrame.height) - 5,
                width: owningScreen.frame.width,
                height: menuBarFrame.height + 5
            )
            setFrame(adjustedFrame, display: true)
            orderFrontRegardless()
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                self.animator().alphaValue = 1
            }
        } catch {
            Logger.appearancePanel.error("Error showing appearance panel: \(error)")
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

// MARK: - ContentView

private class MenuBarAppearancePanelContentView: NSView {
    private var cancellables = Set<AnyCancellable>()

    private weak var appearancePanel: MenuBarAppearancePanel?

    /// The max X position of the main menu.
    private var mainMenuMaxX: CGFloat?

    private weak var appearanceManager: MenuBarAppearanceManager? {
        appearancePanel?.appearanceManager
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

    init(appearancePanel: MenuBarAppearancePanel) {
        self.appearancePanel = appearancePanel
        super.init(frame: .zero)
        configureCancellables()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private func configureCancellables() {
        var c = Set<AnyCancellable>()

        DistributedNotificationCenter.default()
            .publisher(for: Notification.Name("AppleInterfaceThemeChangedNotification"))
            .sink { [weak self] _ in
                guard let self else {
                    return
                }
                alphaValue = 0
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                    ScreenCaptureManager.shared.update()
                    self.animator().alphaValue = 1
                }
            }
            .store(in: &c)

        NSWorkspace.shared.notificationCenter
            .publisher(for: NSWorkspace.activeSpaceDidChangeNotification)
            .sink { _ in
                ScreenCaptureManager.shared.update()
            }
            .store(in: &c)

        NSWorkspace.shared.publisher(for: \.frontmostApplication)
            .sink { _ in
                ScreenCaptureManager.shared.update()
            }
            .store(in: &c)

        ScreenCaptureManager.shared.$windows
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.needsDisplay = true
            }
            .store(in: &c)

        if let appearancePanel {
            appearancePanel.$menuBar
                .sink { [weak self] menuBar in
                    self?.updateMainMenuMaxX(menuBar: menuBar)
                    self?.needsDisplay = true
                }
                .store(in: &c)
            appearancePanel.$desktopWallpaper
                .sink { [weak self] _ in
                    self?.needsDisplay = true
                }
                .store(in: &c)
        }

        if let menuBarManager = appearanceManager?.menuBarManager {
            for name: MenuBarSection.Name in [.visible, .hidden, .alwaysHidden] {
                if let section = menuBarManager.section(withName: name) {
                    section.controlItem.$windowFrame
                        .combineLatest(section.controlItem.$screen)
                        .filter { frame, screen in
                            guard
                                let frame,
                                let screen
                            else {
                                return false
                            }
                            return (screen.frame.minX...screen.frame.maxX).contains(frame.maxX)
                        }
                        .receive(on: RunLoop.main)
                        .sink { [weak self] _ in
                            self?.needsDisplay = true
                        }
                        .store(in: &c)
                }
            }
        }

        if let appearanceManager {
            Publishers.CombineLatest3(
                appearanceManager.$tintKind,
                appearanceManager.$tintColor,
                appearanceManager.$tintGradient
            )
            .combineLatest(
                appearanceManager.$shapeKind,
                appearanceManager.$fullShapeInfo,
                appearanceManager.$splitShapeInfo
            )
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.needsDisplay = true
            }
            .store(in: &c)

            Publishers.CombineLatest4(
                appearanceManager.$hasShadow,
                appearanceManager.$hasBorder,
                appearanceManager.$borderColor,
                appearanceManager.$borderWidth
            )
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.needsDisplay = true
            }
            .store(in: &c)
        }

        cancellables = c
    }

    private func updateMainMenuMaxX(menuBar: UIElement?) {
        Task { @MainActor in
            do {
                guard
                    let menuBar,
                    let children: [UIElement] = try menuBar.arrayAttribute(.children)
                else {
                    mainMenuMaxX = nil
                    return
                }
                mainMenuMaxX = try children.reduce(into: 0) { result, child in
                    if let frame: CGRect = try child.attribute(.frame) {
                        result += frame.width
                    }
                }
            } catch {
                Logger.appearancePanel.error("Error updating main menu maxX: \(error)")
            }
        }
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
            let appearanceManager,
            let menuBarManager = appearanceManager.menuBarManager,
            let hiddenSection = menuBarManager.section(withName: .hidden),
            let alwaysHiddenSection = menuBarManager.section(withName: .alwaysHidden),
            let mainMenuMaxX
        else {
            Logger.appearancePanel.notice("Unable to create split shape path")
            return NSBezierPath(rect: rect)
        }

        guard alwaysHiddenSection.isHidden else {
            let info = MenuBarFullShapeInfo(
                leadingEndCap: info.leading.leadingEndCap,
                trailingEndCap: info.trailing.trailingEndCap
            )
            return pathForFullShapeKind(in: rect, info: info)
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
                let mainScreen = NSScreen.main,
                let owningScreen = appearancePanel?.owningScreen
            else {
                return NSBezierPath(rect: rect)
            }

            let scale = mainScreen.frame.width / owningScreen.frame.width

            var position: CGFloat
            if hiddenSection.isHidden {
                guard let frame = hiddenSection.controlItem.windowFrame else {
                    return NSBezierPath(rect: rect)
                }
                position = (owningScreen.frame.width * scale) - frame.maxX
            } else {
                guard let frame = alwaysHiddenSection.controlItem.windowFrame else {
                    return NSBezierPath(rect: rect)
                }
                position = (owningScreen.frame.width * scale) - frame.maxX
            }

            // offset the position by the origin of the main screen
            position += mainScreen.frame.origin.x

            // add extra padding after the last menu bar item
            position += padding

            // compute the final position based on the maxX of the
            // provided rectangle
            position = rect.maxX - position

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

    override func draw(_ dirtyRect: NSRect) {
        guard
            let appearanceManager,
            let context = NSGraphicsContext.current
        else {
            return
        }

        context.saveGraphicsState()
        defer {
            context.restoreGraphicsState()
        }

        let shapePath = switch appearanceManager.shapeKind {
        case .none:
            NSBezierPath(rect: drawableBounds)
        case .full:
            pathForFullShapeKind(in: drawableBounds, info: appearanceManager.fullShapeInfo)
        case .split:
            pathForSplitShapeKind(in: drawableBounds, info: appearanceManager.splitShapeInfo)
        }

        var hasBorder = false

        if appearanceManager.shapeKind != .none {
            if let desktopWallpaper = appearancePanel?.desktopWallpaper {
                context.saveGraphicsState()
                defer {
                    context.restoreGraphicsState()
                }

                let invertedClipPath = NSBezierPath(rect: drawableBounds)
                invertedClipPath.append(shapePath.reversed)
                invertedClipPath.setClip()

                context.cgContext.draw(desktopWallpaper, in: drawableBounds)
            }

            if appearanceManager.hasShadow {
                context.saveGraphicsState()
                defer {
                    context.restoreGraphicsState()
                }

                let shadowClipPath = NSBezierPath(rect: bounds)
                shadowClipPath.append(shapePath.reversed)
                shadowClipPath.setClip()

                shapePath.drawShadow(color: .black.withAlphaComponent(0.5), radius: 5)
            }

            if appearanceManager.hasBorder {
                hasBorder = true
            }

            shapePath.setClip()

            switch appearanceManager.tintKind {
            case .none:
                break
            case .solid:
                if let tintColor = NSColor(cgColor: appearanceManager.tintColor)?.withAlphaComponent(0.2) {
                    tintColor.setFill()
                    NSBezierPath(rect: drawableBounds).fill()
                }
            case .gradient:
                if let tintGradient = appearanceManager.tintGradient.withAlphaComponent(0.2).nsGradient {
                    tintGradient.draw(in: drawableBounds, angle: 0)
                }
            }

            if
                hasBorder,
                let borderColor = NSColor(cgColor: appearanceManager.borderColor)
            {
                // swiftlint:disable:next force_cast
                let borderPath = shapePath.copy() as! NSBezierPath
                // HACK: insetting a path to get an "inside" stroke is surprisingly
                // difficult; we can fake the correct line width by doubling it, as
                // anything outside the shape path will be clipped
                borderPath.lineWidth = appearanceManager.borderWidth * 2
                borderColor.setStroke()
                borderPath.stroke()
            }
        }
    }
}

// MARK: - Logger
private extension Logger {
    static let appearancePanel = Logger(category: "MenuBarAppearancePanel")
}
