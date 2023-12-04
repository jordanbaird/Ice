//
//  MenuBarAppearancePanel.swift
//  Ice
//

import Cocoa
import Combine

// MARK: - MenuBarAppearancePanel

/// A subclass of `NSPanel` that is displayed over the top
/// of, or underneath the menu bar to alter its appearance.
class MenuBarAppearancePanel: NSPanel {
    /// The default alpha value for menu bar helper panels
    /// of this type.
    class var defaultAlphaValue: CGFloat { 0.2 }

    /// The menu bar that manages this panel.
    private(set) weak var menuBar: MenuBar?

    private var cancellables = Set<AnyCancellable>()

    /// Creates a menu bar helper panel with the given window
    /// level and title.
    /// 
    /// - Parameters:
    ///   - level: The window level of the panel.
    ///   - title: The title of the panel, for accessibility.
    ///   - menuBar: The menu bar responsible for the panel.
    init(level: Level, title: String, menuBar: MenuBar) {
        super.init(
            contentRect: .zero,
            styleMask: [
                .borderless,
                .fullSizeContentView,
                .nonactivatingPanel,
            ],
            backing: .buffered,
            defer: false
        )
        self.menuBar = menuBar
        self.level = level
        self.title = title
        self.backgroundColor = .clear
        self.hasShadow = false
        self.ignoresMouseEvents = true
        self.collectionBehavior = [
            .fullScreenNone,
            .ignoresCycle,
            .moveToActiveSpace,
        ]
        configureCancellables()
    }

    private func configureCancellables() {
        var c = Set<AnyCancellable>()

        NSWorkspace.shared.notificationCenter
            .publisher(for: NSWorkspace.activeSpaceDidChangeNotification)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.hide()
                self?.show(fadeIn: true)
            }
            .store(in: &c)

        cancellables = c
    }

    /// Returns the frame on the given screen that the panel
    /// should treat as the frame of the menu bar.
    ///
    /// - Parameter screen: The screen to use to compute the
    ///   frame of the menu bar.
    func menuBarFrame(forScreen screen: NSScreen) -> CGRect {
        CGRect(
            x: screen.frame.minX,
            y: screen.visibleFrame.maxY + 1,
            width: screen.frame.width,
            height: (screen.frame.height - screen.visibleFrame.height) - 1
        )
    }

    /// Shows the panel.
    ///
    /// - Parameter fadeIn: A Boolean value that indicates whether
    ///   the panel should fade in. If `true`, the panel starts out
    ///   fully transparent and animates its opacity to the value
    ///   returned from the ``defaultAlphaValue`` class property.
    func show(fadeIn: Bool) {
        guard
            !AppState.shared.isPreview,
            let screen = NSScreen.main
        else {
            return
        }
        setFrame(
            menuBarFrame(forScreen: screen),
            display: true
        )
        if fadeIn {
            let isVisible = isVisible
            if !isVisible {
                alphaValue = 0
            }
            orderFrontRegardless()
            if !isVisible {
                animator().alphaValue = Self.defaultAlphaValue
            }
        } else {
            orderFrontRegardless()
            alphaValue = Self.defaultAlphaValue
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

// MARK: - MenuBarOverlayPanel

class MenuBarOverlayPanel: MenuBarAppearancePanel {
    init(menuBar: MenuBar) {
        super.init(
            level: .statusBar,
            title: "Menu Bar Overlay",
            menuBar: menuBar
        )
        self.contentView = MenuBarOverlayPanelView(menuBar: menuBar)
    }
}

// MARK: - MenuBarOverlayPanelView

class MenuBarOverlayPanelView: NSView {
    private(set) weak var menuBar: MenuBar?

    private var cancellables = Set<AnyCancellable>()

    init(menuBar: MenuBar) {
        self.menuBar = menuBar
        super.init(frame: .zero)
        configureCancellables()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private func configureCancellables() {
        var c = Set<AnyCancellable>()

        if let menuBar {
            Publishers.CombineLatest3(
                menuBar.$tintKind,
                menuBar.$tintColor,
                menuBar.$tintGradient
            )
            .combineLatest(
                menuBar.$shapeKind,
                menuBar.$fullShapeInfo,
                menuBar.$splitShapeInfo
            )
            .sink { [weak self] _ in
                self?.needsDisplay = true
            }
            .store(in: &c)
        }

        cancellables = c
    }

    override func draw(_ dirtyRect: NSRect) {
        NSGraphicsContext.saveGraphicsState()
        defer {
            NSGraphicsContext.restoreGraphicsState()
        }

        guard let menuBar else {
            return
        }

        switch menuBar.shapeKind {
        case .none:
            break
        case .full:
            let clipBounds = CGRect(
                x: bounds.height / 2,
                y: 0,
                width: bounds.width - bounds.height,
                height: bounds.height
            )
            let leadingEndCapBounds = CGRect(
                x: 0,
                y: 0,
                width: bounds.height,
                height: bounds.height
            )
            let trailingEndCapBounds = CGRect(
                x: bounds.width - bounds.height,
                y: 0,
                width: bounds.height,
                height: bounds.height
            )

            let clipPath = NSBezierPath(rect: clipBounds)

            switch menuBar.fullShapeInfo.leadingEndCap {
            case .square:
                clipPath.appendRect(leadingEndCapBounds)
            case .round:
                clipPath.appendOval(in: leadingEndCapBounds)
            }

            switch menuBar.fullShapeInfo.trailingEndCap {
            case .square:
                clipPath.appendRect(trailingEndCapBounds)
            case .round:
                clipPath.appendOval(in: trailingEndCapBounds)
            }

            clipPath.setClip()
        case .split:
            break
        }

        switch menuBar.tintKind {
        case .none:
            break
        case .solid:
            NSColor(cgColor: menuBar.tintColor)?.setFill()
            NSBezierPath(rect: bounds).fill()
        case .gradient:
            menuBar.tintGradient.nsGradient?.draw(in: bounds, angle: 0)
        }
    }
}

// MARK: - MenuBarBackingPanel

class MenuBarBackingPanel: MenuBarAppearancePanel {
    override class var defaultAlphaValue: CGFloat { 1 }

    private var offset: Double {
        guard
            let menuBar,
            menuBar.hasBorder
        else {
            return 0
        }
        return menuBar.borderWidth
    }

    init(menuBar: MenuBar) {
        super.init(
            level: Level(Int(CGWindowLevelForKey(.desktopIconWindow))),
            title: "Menu Bar Backing",
            menuBar: menuBar
        )
        self.contentView = MenuBarBackingPanelView(menuBar: menuBar)
    }

    override func menuBarFrame(forScreen screen: NSScreen) -> CGRect {
        let rect = super.menuBarFrame(forScreen: screen)
        return CGRect(
            x: rect.minX,
            y: (rect.minY - offset) - 5,
            width: rect.width,
            height: (rect.height + offset) + 5
        )
    }
}

// MARK: - MenuBarBackingPanelView

class MenuBarBackingPanelView: NSView {
    private(set) weak var menuBar: MenuBar?

    private var cancellables = Set<AnyCancellable>()

    init(menuBar: MenuBar) {
        self.menuBar = menuBar
        super.init(frame: .zero)
        configureCancellables()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private func configureCancellables() {
        var c = Set<AnyCancellable>()

        if let menuBar {
            Publishers.CombineLatest4(
                menuBar.$hasShadow,
                menuBar.$hasBorder,
                menuBar.$borderColor,
                menuBar.$borderWidth
            )
            .sink { [weak self] _ in
                self?.needsDisplay = true
            }
            .store(in: &c)
        }

        cancellables = c
    }

    override func draw(_ dirtyRect: NSRect) {
        guard let menuBar else {
            return
        }
        if menuBar.hasShadow {
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
        if menuBar.hasBorder {
            let borderBounds = CGRect(
                x: bounds.minX,
                y: bounds.minY + 5,
                width: bounds.width,
                height: menuBar.borderWidth
            )
            NSColor(cgColor: menuBar.borderColor)?.setFill()
            NSBezierPath(rect: borderBounds).fill()
        }
    }
}
