//
//  MenuBarAppearancePanel_Old.swift
//  Ice
//

import Cocoa
import Combine

// MARK: - MenuBarAppearancePanel

/// A subclass of `NSPanel` that is displayed over the top
/// of, or underneath the menu bar to alter its appearance.
class MenuBarAppearancePanel_Old: NSPanel {
    private var cancellables = Set<AnyCancellable>()

    /// The appearance manager that manages the panel.
    private(set) weak var appearanceManager: MenuBarAppearanceManager?

    /// Creates a panel with the given window level and menu bar.
    ///
    /// - Parameters:
    ///   - level: The window level of the panel.
    ///   - appearanceManager: The appearance manager that manages the panel.
    init(level: Level, appearanceManager: MenuBarAppearanceManager) {
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
        self.appearanceManager = appearanceManager
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

        // always show the panel on the active space
        NSWorkspace.shared.notificationCenter
            .publisher(for: NSWorkspace.activeSpaceDidChangeNotification)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                guard
                    let self,
                    let screen = NSScreen.main
                else {
                    return
                }

                // cache isVisible before hiding
                let isVisible = isVisible

                hide()

                // if the screen's visible frame and frame are the same,
                // the menu bar is hidden; do not allow the panel to show
                let canShow = screen.visibleFrame != screen.frame

                if canShow && isVisible {
                    show()
                }
            }
            .store(in: &c)

        // ensure the panel stays pinned to the top of the screen
        // if the size of the screen changes, i.e. when scaling a
        // VM window
        Timer.publish(every: 1, on: .main, in: .common)
            .autoconnect()
            .sink { [weak self] _ in
                guard
                    let self,
                    let screen
                else {
                    return
                }
                setFrame(menuBarFrame(forScreen: screen), display: true)
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
        guard
            let menuBarManager = appearanceManager?.menuBarManager,
            let menuBarFrame: CGRect = try? menuBarManager.menuBar?.attribute(.frame)
        else {
            return .zero
        }
        return CGRect(
            x: menuBarFrame.origin.x,
            y: screen.frame.maxY - menuBarFrame.origin.y - menuBarFrame.height,
            width: menuBarFrame.width,
            height: menuBarFrame.height
        )
    }

    /// Shows the panel.
    func show() {
        guard
            !AppState.shared.isPreview,
            let screen = NSScreen.main
        else {
            return
        }
        setFrame(menuBarFrame(forScreen: screen), display: true)
        let isVisible = isVisible
        if !isVisible {
            alphaValue = 0
        }
        orderFrontRegardless()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            if !isVisible {
                self.animator().alphaValue = 1
            }
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
