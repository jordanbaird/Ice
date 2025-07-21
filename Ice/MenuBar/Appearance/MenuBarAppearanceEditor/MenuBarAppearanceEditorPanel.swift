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
            styleMask: [.titled, .closable, .fullSizeContentView, .nonactivatingPanel, .utilityWindow, .hudWindow],
            backing: .buffered,
            defer: false
        )
        self.titlebarAppearsTransparent = true
        self.isExcludedFromWindowsMenu = false
        self.becomesKeyOnlyIfNeeded = true
        self.isMovableByWindowBackground = false
        self.isMovable = false
        self.hidesOnDeactivate = false
        self.level = .floating
        self.collectionBehavior = [.fullScreenAuxiliary, .ignoresCycle, .moveToActiveSpace]
        standardWindowButton(.closeButton)?.isHidden = true
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

        // Close the panel when certain app or system events occur.
        Publishers.Merge3(
            NSWorkspace.shared.notificationCenter.publisher(for: NSWorkspace.activeSpaceDidChangeNotification),
            NotificationCenter.default.publisher(for: NSApplication.didChangeScreenParametersNotification),
            NotificationCenter.default.publisher(for: NSApplication.didResignActiveNotification)
        )
        .sink { [weak self] _ in
            self?.close()
        }
        .store(in: &c)

        cancellables = c
    }

    /// Updates the origin of the panel's frame for display
    /// on the given screen.
    private func updateOrigin(for screen: NSScreen) {
        let originX = screen.frame.midX - frame.width / 2
        let originY = screen.visibleFrame.maxY - frame.height
        setFrameOrigin(CGPoint(x: originX, y: originY))
    }

    /// Shows the panel on the given screen.
    func show(on screen: NSScreen) {
        updateOrigin(for: screen)
        makeKeyAndOrderFront(nil)
    }

    override func cancelOperation(_ sender: Any?) {
        super.cancelOperation(sender)
        close()
    }
}

// MARK: - MenuBarAppearanceEditorHostingView

private final class MenuBarAppearanceEditorHostingView: NSHostingView<MenuBarAppearanceEditorContentView> {
    override var acceptsFirstResponder: Bool { true }
    override var needsPanelToBecomeKey: Bool { true }

    override var safeAreaInsets: NSEdgeInsets { NSEdgeInsets() }
    override var intrinsicContentSize: CGSize { CGSize(width: 550, height: 600) }

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
        MenuBarAppearanceEditor(location: .panel)
            .background {
                Rectangle()
                    .fill(.regularMaterial)
                Rectangle()
                    .fill(.windowBackground)
                    .opacity(0.25)
            }
            .environmentObject(appState)
            .environmentObject(appState.appearanceManager)
    }
}
