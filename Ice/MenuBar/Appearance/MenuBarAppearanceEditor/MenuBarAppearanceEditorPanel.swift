//
//  MenuBarAppearanceEditorPanel.swift
//  Ice
//

import Combine
import SwiftUI

/// A panel that contains a portable version of the menu bar
/// appearance editor interface.
final class MenuBarAppearanceEditorPanel: NSPanel {
    /// The default screen to show the panel on.
    static var defaultScreen: NSScreen? {
        NSScreen.screenWithMouse ?? NSScreen.main
    }

    /// The shared app state.
    private weak var appState: AppState?

    /// Storage for internal observers.
    private var cancellables = Set<AnyCancellable>()

    /// Overridden to always be `true`.
    override var canBecomeKey: Bool { true }

    /// Creates a menu bar appearance editor panel.
    init() {
        super.init(
            contentRect: .zero,
            styleMask: [.titled, .closable, .fullSizeContentView, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        self.title = "Menu Bar Appearance"
        self.titlebarAppearsTransparent = true
        self.allowsToolTipsWhenApplicationIsInactive = true
        self.isFloatingPanel = true
        self.hidesOnDeactivate = false
        self.isMovableByWindowBackground = false
        self.collectionBehavior = [.fullScreenAuxiliary, .moveToActiveSpace]
    }

    /// Sets up the panel.
    func performSetup(with appState: AppState) {
        self.appState = appState
        configureContentView(with: appState)
        configureCancellables()
    }

    /// Configures the panel's content view.
    private func configureContentView(with appState: AppState) {
        let hostingView = MenuBarAppearanceEditorHostingView(appState: appState)
        setFrame(hostingView.frame, display: true)
        contentView = hostingView
    }

    /// Configures the internal observers for the panel.
    private func configureCancellables() {
        var c = Set<AnyCancellable>()

        // Make sure the panel takes on the app's appearance.
        NSApp.publisher(for: \.effectiveAppearance)
            .sink { [weak self] effectiveAppearance in
                self?.appearance = effectiveAppearance
            }
            .store(in: &c)

        publisher(for: \.isVisible)
            .sink { isVisible in
                if isVisible {
                    NSColorPanel.shared.hidesOnDeactivate = false
                } else {
                    NSColorPanel.shared.hidesOnDeactivate = true
                    NSColorPanel.shared.close()
                }
            }
            .store(in: &c)

        cancellables = c
    }

    /// Updates the panel's position for display on the given screen.
    private func updatePosition(for screen: NSScreen) {
        let originX = screen.visibleFrame.midX - frame.width / 2
        let originY = screen.visibleFrame.maxY
        setFrameTopLeftPoint(CGPoint(x: originX, y: originY))
    }

    /// Shows the panel on the given screen.
    func show(on screen: NSScreen) {
        updatePosition(for: screen)
        makeKeyAndOrderFront(nil)
    }
}

// MARK: - MenuBarAppearanceEditorHostingView

private final class MenuBarAppearanceEditorHostingView: NSHostingView<MenuBarAppearanceEditorContentView> {
    override var intrinsicContentSize: CGSize {
        CGSize(width: 550, height: 600)
    }

    init(appState: AppState) {
        super.init(rootView: MenuBarAppearanceEditorContentView(appState: appState))
        setFrameSize(intrinsicContentSize)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    @available(*, unavailable)
    required init(rootView: MenuBarAppearanceEditorContentView) {
        fatalError("init(rootView:) has not been implemented")
    }
}

// MARK: - MenuBarAppearanceEditorContentView

private struct MenuBarAppearanceEditorContentView: View {
    @ObservedObject var appState: AppState

    var body: some View {
        MenuBarAppearanceEditor(
            appearanceManager: appState.appearanceManager,
            location: .panel
        )
        .environmentObject(appState)
    }
}
