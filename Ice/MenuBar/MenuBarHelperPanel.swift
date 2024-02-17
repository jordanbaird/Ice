//
//  MenuBarHelperPanel.swift
//  Ice
//

import SwiftUI

// MARK: - MenuBarHelperPanel

/// A panel that manages the menu that appears when the user
/// right-clicks on the menu bar.
class MenuBarHelperPanel: NSPanel {
    /// A Boolean value that indicates whether the panel is
    /// currently showing the appearance editor popover.
    private var isShowingPopover = false

    init(origin: CGPoint) {
        super.init(
            contentRect: CGRect(origin: origin, size: CGSize(width: 1, height: 1)),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        level = .statusBar
        backgroundColor = .clear
    }

    /// Shows the right-click menu.
    func showMenu() {
        let menu = NSMenu(title: Constants.appName)
        menu.delegate = self

        let editItem = NSMenuItem(
            title: "Edit Menu Bar Appearance…",
            action: #selector(showAppearanceEditorPopover),
            keyEquivalent: ""
        )
        editItem.target = self
        menu.addItem(editItem)

        menu.addItem(.separator())

        let settingsItem = NSMenuItem(
            title: "\(Constants.appName) Settings…",
            action: #selector(AppDelegate.openSettingsWindow),
            keyEquivalent: ","
        )
        menu.addItem(settingsItem)

        menu.popUp(positioning: nil, at: frame.origin, in: nil)
    }

    /// Shows the appearance editor popover, centered under
    /// the menu bar.
    @objc private func showAppearanceEditorPopover() {
        guard
            let contentView,
            let screen
        else {
            return
        }
        setFrameOrigin(CGPoint(x: screen.frame.midX - (frame.width / 2), y: screen.visibleFrame.maxY))
        let popover = MenuBarAppearanceEditorPopover()
        popover.delegate = self
        popover.show(relativeTo: .zero, of: contentView, preferredEdge: .minY)
        isShowingPopover = true
    }
}

// MARK: MenuBarHelperPanel: NSMenuDelegate
extension MenuBarHelperPanel: NSMenuDelegate {
    func menuDidClose(_ menu: NSMenu) {
        // async so that `isShowingPopover` has a chance to get set
        DispatchQueue.main.async { [self] in
            guard !isShowingPopover else {
                return
            }
            orderOut(menu)
        }
    }
}

// MARK: MenuBarHelperPanel: NSPopoverDelegate
extension MenuBarHelperPanel: NSPopoverDelegate {
    func popoverDidClose(_ notification: Notification) {
        guard let popover = notification.object as? MenuBarAppearanceEditorPopover else {
            return
        }
        isShowingPopover = false
        orderOut(popover)
        popover.mouseDownMonitor.stop()
    }
}

// MARK: - MenuBarAppearanceEditorPopover

/// A popover that displays the menu bar appearance editor at
/// a centered location under the menu bar.
private class MenuBarAppearanceEditorPopover: NSPopover {
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
