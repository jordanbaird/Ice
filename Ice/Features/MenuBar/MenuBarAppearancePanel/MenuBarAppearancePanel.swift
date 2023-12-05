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
    private var cancellables = Set<AnyCancellable>()

    /// The menu bar that manages the panel.
    private(set) weak var menuBar: MenuBar?

    /// The default alpha value for the panel.
    var defaultAlphaValue: CGFloat { 0.2 }

    /// A Boolean value that indicates whether the panel
    /// can be shown.
    var canShow: Bool { true }

    /// Creates a panel with the given window level and
    /// menu bar.
    ///
    /// - Parameters:
    ///   - level: The window level of the panel.
    ///   - menuBar: The menu bar that manages the panel.
    init(level: Level, menuBar: MenuBar) {
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
        self.title = String(describing: Self.self)
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

    /// Shows the panel.
    ///
    /// - Parameter fadeIn: A Boolean value that indicates whether
    ///   the panel should fade in. If `true`, the panel starts out
    ///   fully transparent and animates its opacity to the value
    ///   returned from the ``defaultAlphaValue`` property.
    func showIfAble(fadeIn: Bool) {
        guard
            canShow,
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
                animator().alphaValue = defaultAlphaValue
            }
        } else {
            orderFrontRegardless()
            alphaValue = defaultAlphaValue
        }
    }

    /// Hides the panel.
    func hide() {
        if isVisible {
            close()
        }
    }

    override func isAccessibilityElement() -> Bool {
        return false
    }
}
