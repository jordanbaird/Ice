//
//  MenuBarAppearanceEditorHelperPanel.swift
//  Ice
//

import SwiftUI

// MARK: - MenuBarAppearanceEditorHelperPanel

/// A panel that manages the menu that appears when the user
/// right-clicks on the menu bar.
class MenuBarAppearanceEditorHelperPanel: NSPanel {
    init() {
        super.init(
            contentRect: CGRect(x: 0, y: 0, width: 1, height: 1),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        level = .statusBar
        backgroundColor = .clear
    }

    /// Shows the appearance editor popover.
    func showAppearanceEditorPopover() {
        guard
            let contentView,
            let screen = NSScreen.screens.first(where: { $0.frame.contains(NSEvent.mouseLocation) })
        else {
            return
        }
        setFrameOrigin(CGPoint(x: screen.frame.midX - frame.width / 2, y: screen.visibleFrame.maxY))
        let popover = MenuBarAppearanceEditorPopover()
        popover.delegate = self
        popover.show(relativeTo: .zero, of: contentView, preferredEdge: .minY)
    }
}

// MARK: MenuBarAppearanceEditorHelperPanel: NSPopoverDelegate
extension MenuBarAppearanceEditorHelperPanel: NSPopoverDelegate {
    func popoverDidClose(_ notification: Notification) {
        if let popover = notification.object as? MenuBarAppearanceEditorPopover {
            popover.mouseDownMonitor.stop()
            orderOut(popover)
        }
    }
}

// MARK: - MenuBarAppearanceEditorPopover

/// A popover that displays the menu bar appearance editor
/// at a centered location under the menu bar.
class MenuBarAppearanceEditorPopover: NSPopover {
    private(set) lazy var mouseDownMonitor = GlobalEventMonitor(mask: .leftMouseDown) { [weak self] event in
        self?.performClose(self)
    }

    @ViewBuilder
    private var contentView: some View {
        VStack {
            Text("Menu Bar Appearance")
                .font(.title2)
                .padding(.top)

            MenuBarAppearanceTab()
                .padding(.top, -14)
                .environmentObject(AppState.shared)

            HStack {
                Spacer()
                Button("Done") { [weak self] in
                    self?.performClose(self)
                }
                .controlSize(.large)
            }
            .padding()
        }
    }

    override init() {
        super.init()
        self.contentViewController = NSHostingController(rootView: contentView)
        self.contentSize = CGSize(width: 500, height: 500)
        self.behavior = .applicationDefined
        self.mouseDownMonitor.start()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
}
