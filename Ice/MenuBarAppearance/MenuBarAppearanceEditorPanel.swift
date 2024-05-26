//
//  MenuBarAppearanceEditorPanel.swift
//  Ice
//

import Combine
import SwiftUI

// MARK: - MenuBarAppearanceEditorPanel

/// A panel that manages the appearance editor popover.
class MenuBarAppearanceEditorPanel: NSPanel {
    private var cancellables = Set<AnyCancellable>()

    init() {
        super.init(
            contentRect: CGRect(x: 0, y: 0, width: 1, height: 1),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        level = .statusBar
        backgroundColor = .clear
        configureCancellables()
    }

    private func configureCancellables() {
        var c = Set<AnyCancellable>()

        NSWorkspace.shared.notificationCenter
            .publisher(for: NSWorkspace.activeSpaceDidChangeNotification)
            .sink { [weak self] _ in
                self?.orderOut(self)
                NSColorPanel.shared.close()
                NSColorPanel.shared.hidesOnDeactivate = true
            }
            .store(in: &c)

        cancellables = c
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
        popover.contentViewController?.view.window?.makeKey()
        NSColorPanel.shared.hidesOnDeactivate = false
    }
}

// MARK: MenuBarAppearanceEditorPanel: NSPopoverDelegate
extension MenuBarAppearanceEditorPanel: NSPopoverDelegate {
    func popoverDidClose(_ notification: Notification) {
        if let popover = notification.object as? MenuBarAppearanceEditorPopover {
            popover.mouseDownMonitor.stop()
            orderOut(popover)
            NSColorPanel.shared.close()
            NSColorPanel.shared.hidesOnDeactivate = true
        }
    }
}

// MARK: - MenuBarAppearanceEditorPopover

/// A popover that displays the menu bar appearance editor
/// at a centered location under the menu bar.
private class MenuBarAppearanceEditorPopover: NSPopover {
    private(set) lazy var mouseDownMonitor = GlobalEventMonitor(mask: .leftMouseDown) { [weak self] _ in
        self?.performClose(self)
    }

    @ViewBuilder
    private var contentView: some View {
        MenuBarAppearanceEditor(
            location: .popover(closePopover: { [weak self] in
                self?.performClose(self)
            })
        )
        .environmentObject(AppState.shared)
        .buttonStyle(.custom)
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
