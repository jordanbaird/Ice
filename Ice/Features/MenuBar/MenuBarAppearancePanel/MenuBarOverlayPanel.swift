//
//  MenuBarOverlayPanel.swift
//  Ice
//

import Cocoa
import Combine

// MARK: - MenuBarOverlayPanel

class MenuBarOverlayPanel: MenuBarAppearancePanel {
    init(menuBar: MenuBar) {
        super.init(level: .statusBar)
        self.contentView = MenuBarOverlayPanelView(menuBar: menuBar)
    }
}

// MARK: - MenuBarOverlayPanelView

private class MenuBarOverlayPanelView: NSView {
    private weak var menuBar: MenuBar?
    private var cancellable: (any Cancellable)?

    init(menuBar: MenuBar) {
        super.init(frame: .zero)
        self.menuBar = menuBar
        self.cancellable = Publishers.CombineLatest3(
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
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
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
