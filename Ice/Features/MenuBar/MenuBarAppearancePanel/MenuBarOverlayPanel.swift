//
//  MenuBarOverlayPanel.swift
//  Ice
//

import Cocoa
import Combine

// MARK: - MenuBarOverlayPanel

class MenuBarOverlayPanel: MenuBarAppearancePanel {
    private var cancellables = Set<AnyCancellable>()

    init(menuBar: MenuBar) {
        super.init(level: .statusBar, menuBar: menuBar)
        self.contentView = MenuBarOverlayPanelView(menuBar: menuBar)
    }

    func configureCancellables() {
        var c = Set<AnyCancellable>()

        if let menuBar {
            Publishers.CombineLatest(
                menuBar.$tintKind,
                menuBar.$shapeKind
            )
            .map { tintKind, shapeKind in
                tintKind != .none || shapeKind != .none
            }
            .receive(on: DispatchQueue.main)
            .sink { [weak self] shouldShow in
                guard let self else {
                    return
                }
                if shouldShow {
                    show()
                } else {
                    hide()
                }
            }
            .store(in: &c)
        }

        cancellables = c
    }
}

// MARK: - MenuBarOverlayPanelView

private class MenuBarOverlayPanelView: NSView {
    private weak var menuBar: MenuBar?
    private var cancellables = Set<AnyCancellable>()

    init(menuBar: MenuBar) {
        super.init(frame: .zero)
        self.menuBar = menuBar
        configureCancellables()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private func configureCancellables() {
        var c = Set<AnyCancellable>()

        if let menuBar {
            Publishers.CombineLatest4(
                menuBar.$desktopWallpaper,
                menuBar.$tintKind,
                menuBar.$tintColor,
                menuBar.$tintGradient
            )
            .combineLatest(
                menuBar.$shapeKind,
                menuBar.$fullShapeInfo,
                menuBar.$splitShapeInfo
            )
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.needsDisplay = true
            }
            .store(in: &c)

            Publishers.CombineLatest4(
                menuBar.$hasShadow,
                menuBar.$hasBorder,
                menuBar.$borderColor,
                menuBar.$borderWidth
            )
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.needsDisplay = true
            }
            .store(in: &c)
        }

        cancellables = c
    }

    override func draw(_ dirtyRect: NSRect) {
        guard
            let menuBar,
            let context = NSGraphicsContext.current
        else {
            return
        }

        context.saveGraphicsState()
        defer {
            context.restoreGraphicsState()
        }

        var shapePath: NSBezierPath

        switch menuBar.shapeKind {
        case .none:
            shapePath = NSBezierPath(rect: bounds)
        case .full:
            let shapeBounds = CGRect(
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

            shapePath = NSBezierPath(rect: shapeBounds)

            switch menuBar.fullShapeInfo.leadingEndCap {
            case .square:
                shapePath = shapePath.union(NSBezierPath(rect: leadingEndCapBounds))
            case .round:
                shapePath = shapePath.union(NSBezierPath(ovalIn: leadingEndCapBounds))
            }

            switch menuBar.fullShapeInfo.trailingEndCap {
            case .square:
                shapePath = shapePath.union(NSBezierPath(rect: trailingEndCapBounds))
            case .round:
                shapePath = shapePath.union(NSBezierPath(ovalIn: trailingEndCapBounds))
            }

            if let desktopWallpaper = menuBar.desktopWallpaper {
                let reversedClipPath = NSBezierPath(rect: bounds)
                reversedClipPath.append(shapePath.reversed)
                reversedClipPath.setClip()
                context.cgContext.draw(desktopWallpaper, in: bounds, byTiling: false)
            }

            shapePath.setClip()
        case .split:
            shapePath = NSBezierPath(rect: bounds)
        }

        switch menuBar.tintKind {
        case .none:
            break
        case .solid:
            if let tintColor = NSColor(cgColor: menuBar.tintColor)?.withAlphaComponent(0.2) {
                tintColor.setFill()
                NSBezierPath(rect: bounds).fill()
            }
        case .gradient:
            if let tintGradient = menuBar.tintGradient.withAlphaComponent(0.2).nsGradient {
                tintGradient.draw(in: bounds, angle: 0)
            }
        }

        if
            menuBar.hasBorder,
            menuBar.shapeKind != .none
        {
            if let borderColor = NSColor(cgColor: menuBar.borderColor) {
                borderColor.setStroke()

                let translation = menuBar.borderWidth / 2
                let scaleX = (bounds.width - menuBar.borderWidth) / bounds.width
                let scaleY = (bounds.height - menuBar.borderWidth) / bounds.height
                var transform = CGAffineTransform(translationX: translation, y: translation).scaledBy(x: scaleX, y: scaleY)

                if let transformedPath = shapePath.cgPath.copy(using: &transform) {
                    let borderPath = NSBezierPath(cgPath: transformedPath)
                    borderPath.lineWidth = menuBar.borderWidth
                    borderPath.stroke()
                }
            }
        }
    }
}
