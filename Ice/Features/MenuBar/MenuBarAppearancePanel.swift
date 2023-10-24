//
//  MenuBarAppearancePanel.swift
//  Ice
//

import Cocoa
import Combine
import OSLog

// MARK: - MenuBarAppearancePanel

/// A subclass of `NSPanel` that is displayed over the top
/// of, or underneath the menu bar to alter its appearance.
class MenuBarAppearancePanel: NSPanel {
    /// The default alpha value for menu bar helper panels
    /// of this type.
    class var defaultAlphaValue: CGFloat { 0.2 }

    /// The menu bar manager that manages this panel.
    private(set) weak var menuBarManager: MenuBarManager?

    private var cancellables = Set<AnyCancellable>()

    /// A Boolean value that indicates whether the panel can
    /// be shown using ``showIfAble(fadeIn:)``.
    var canShow: Bool { true }

    /// Creates a menu bar helper panel with the given window
    /// level and title.
    /// 
    /// - Parameters:
    ///   - level: The window level of the panel.
    ///   - title: The title of the panel, for accessibility.
    ///   - menuBarManager: The menu bar manager responsible for
    ///     the panel.
    init(level: Level, title: String, menuBarManager: MenuBarManager) {
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
        self.menuBarManager = menuBarManager
        self.level = level
        self.title = title
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
                self?.showIfAble(fadeIn: true)
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

    /// Shows the panel, if it is able to be shown.
    ///
    /// If ``canShow`` returns `true`, the panel will show.
    ///
    /// - Parameter fadeIn: A Boolean value that indicates whether
    ///   the panel should fade in. If `true`, the panel starts out
    ///   fully transparent and animates its opacity to the value
    ///   returned from the ``defaultAlphaValue`` class property.
    func showIfAble(fadeIn: Bool) {
        guard
            canShow,
            !ProcessInfo.processInfo.isPreview
        else {
            return
        }
        guard let screen = NSScreen.main else {
            Logger.menuBarAppearancePanel.info("No screen")
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
    private var cancellables = Set<AnyCancellable>()

    override var canShow: Bool {
        guard let tintKind = menuBarManager?.tintKind else {
            return false
        }
        return tintKind != .none
    }

    init(menuBarManager: MenuBarManager) {
        super.init(
            level: .statusBar,
            title: "Menu Bar Overlay",
            menuBarManager: menuBarManager
        )
        self.contentView?.wantsLayer = true
        configureCancellables()
    }

    private func configureCancellables() {
        var c = Set<AnyCancellable>()

        if let menuBarManager {
            Publishers.CombineLatest3(
                menuBarManager.$tintKind,
                menuBarManager.$tintColor,
                menuBarManager.$tintGradient
            )
            .sink { [weak self] _ in
                DispatchQueue.main.async {
                    self?.updateTint()
                }
            }
            .store(in: &c)
        }

        cancellables = c
    }

    /// Updates the tint of the panel according to the menu bar
    /// manager's tint kind.
    func updateTint() {
        backgroundColor = .clear
        contentView?.layer = CALayer()

        guard let menuBarManager else {
            return
        }

        switch menuBarManager.tintKind {
        case .none:
            break
        case .solid:
            guard
                let tintColor = menuBarManager.tintColor,
                let nsColor = NSColor(cgColor: tintColor)
            else {
                return
            }
            backgroundColor = nsColor
        case .gradient:
            guard !menuBarManager.tintGradient.stops.isEmpty else {
                return
            }
            let gradientLayer = CAGradientLayer()
            gradientLayer.startPoint = CGPoint(x: 0, y: 0)
            gradientLayer.endPoint = CGPoint(x: 1, y: 0)
            if menuBarManager.tintGradient.stops.count == 1 {
                // gradient layer needs at least two stops to render correctly;
                // convert the single stop into two and place them on opposite
                // ends of the layer
                let color = menuBarManager.tintGradient.stops[0].color
                gradientLayer.colors = [color, color]
                gradientLayer.locations = [0, 1]
            } else {
                let sortedStops = menuBarManager.tintGradient.stops.sorted { $0.location < $1.location }
                gradientLayer.colors = sortedStops.map { $0.color }
                gradientLayer.locations = sortedStops.map { $0.location } as [NSNumber]
            }
            contentView?.layer = gradientLayer
        }
    }
}

// MARK: - MenuBarShadowPanel
class MenuBarShadowPanel: MenuBarAppearancePanel {
    override class var defaultAlphaValue: CGFloat { 1 }

    override var canShow: Bool {
        menuBarManager?.hasShadow ?? false
    }

    init(menuBarManager: MenuBarManager) {
        super.init(
            level: Level(Int(CGWindowLevelForKey(.desktopIconWindow))),
            title: "Menu Bar Shadow",
            menuBarManager: menuBarManager
        )
        self.backgroundColor = .clear
        self.contentView?.wantsLayer = true
        let gradientLayer = CAGradientLayer()
        gradientLayer.colors = [CGColor.clear, CGColor(gray: 0, alpha: 0.2)]
        self.contentView?.layer = gradientLayer
    }

    override func menuBarFrame(forScreen screen: NSScreen) -> CGRect {
        let rect = super.menuBarFrame(forScreen: screen)
        return CGRect(
            x: rect.minX,
            y: rect.minY - 5,
            width: rect.width,
            height: 5
        )
    }
}

// MARK: - Logger
private extension Logger {
    static let menuBarAppearancePanel = mainSubsystem(category: "MenuBarAppearancePanel")
}
