//
//  MenuBarBackingPanel.swift
//  Ice
//

import Cocoa
import Combine

// MARK: - MenuBarBackingPanel

class MenuBarBackingPanel: MenuBarAppearancePanel {
    override var defaultAlphaValue: CGFloat { 1 }

    override var canShow: Bool {
        guard let menuBar else {
            return false
        }
        return menuBar.hasShadow || menuBar.hasBorder
    }

    init(menuBar: MenuBar) {
        super.init(level: Level(Int(CGWindowLevelForKey(.desktopIconWindow))), menuBar: menuBar)
        self.contentView = MenuBarBackingPanelView(menuBar: menuBar)
    }

    override func menuBarFrame(forScreen screen: NSScreen) -> CGRect {
        let rect = super.menuBarFrame(forScreen: screen)
        let offset: CGFloat = {
            guard
                let menuBar,
                menuBar.hasBorder
            else {
                return 0
            }
            return menuBar.borderWidth
        }()
        return CGRect(
            x: rect.minX,
            y: (rect.minY - offset) - 5,
            width: rect.width,
            height: (rect.height + offset) + 5
        )
    }
}

// MARK: - MenuBarBackingPanelView

private class MenuBarBackingPanelView: NSView {
    private weak var menuBar: MenuBar?
    private var cancellable: (any Cancellable)?

    init(menuBar: MenuBar) {
        super.init(frame: .zero)
        self.menuBar = menuBar
        self.cancellable = Publishers.CombineLatest4(
            menuBar.$hasShadow,
            menuBar.$hasBorder,
            menuBar.$borderColor,
            menuBar.$borderWidth
        )
        .sink { [weak self] _ in
            self?.needsDisplay = true
        }
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
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
