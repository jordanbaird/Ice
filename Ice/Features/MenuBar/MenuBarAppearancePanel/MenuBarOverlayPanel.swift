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
            Publishers.CombineLatest3(
                menuBar.$tintKind,
                menuBar.$shapeKind,
                menuBar.$hasShadow
            )
            .map { tintKind, shapeKind, _ in
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

    override func menuBarFrame(forScreen screen: NSScreen) -> CGRect {
        let rect = super.menuBarFrame(forScreen: screen)
        return CGRect(
            x: rect.minX,
            y: rect.minY - 5,
            width: rect.width,
            height: rect.height + 5
        )
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

        let adjustedBounds = CGRect(
            x: bounds.origin.x,
            y: bounds.origin.y + 5,
            width: bounds.width,
            height: bounds.height - 5
        )

        var shapePath: NSBezierPath

        switch menuBar.shapeKind {
        case .none:
            shapePath = NSBezierPath(rect: adjustedBounds)
        case .full:
            let shapeBounds = CGRect(
                x: adjustedBounds.height / 2,
                y: adjustedBounds.origin.y,
                width: adjustedBounds.width - adjustedBounds.height,
                height: adjustedBounds.height
            )
            let leadingEndCapBounds = CGRect(
                x: adjustedBounds.origin.x,
                y: adjustedBounds.origin.y,
                width: adjustedBounds.height,
                height: adjustedBounds.height
            )
            let trailingEndCapBounds = CGRect(
                x: adjustedBounds.width - adjustedBounds.height,
                y: adjustedBounds.origin.y,
                width: adjustedBounds.height,
                height: adjustedBounds.height
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
        case .split:
            shapePath = NSBezierPath(rect: adjustedBounds)
        }

        if
            let desktopWallpaper = menuBar.desktopWallpaper,
            menuBar.shapeKind != .none
        {
            context.saveGraphicsState()
            defer {
                context.restoreGraphicsState()
            }

            let reversedClipPath = NSBezierPath(rect: adjustedBounds)
            reversedClipPath.append(shapePath.reversed)
            reversedClipPath.setClip()

            context.cgContext.draw(desktopWallpaper, in: adjustedBounds, byTiling: false)
        }

        if
            menuBar.hasShadow,
            menuBar.shapeKind != .none
        {
            context.saveGraphicsState()
            defer {
                context.restoreGraphicsState()
            }

            let shadowClipPath = NSBezierPath(rect: bounds)
            shadowClipPath.append(shapePath.reversed)
            shadowClipPath.setClip()

            shapePath.drawShadow(color: .black.withAlphaComponent(0.5), radius: 5)
        }

        shapePath.setClip()

        switch menuBar.tintKind {
        case .none:
            break
        case .solid:
            if let tintColor = NSColor(cgColor: menuBar.tintColor)?.withAlphaComponent(0.2) {
                tintColor.setFill()
                NSBezierPath(rect: adjustedBounds).fill()
            }
        case .gradient:
            if let tintGradient = menuBar.tintGradient.withAlphaComponent(0.2).nsGradient {
                tintGradient.draw(in: adjustedBounds, angle: 0)
            }
        }

        if
            menuBar.hasBorder,
            menuBar.shapeKind != .none
        {
            if let borderColor = NSColor(cgColor: menuBar.borderColor) {
                borderColor.setStroke()

                let translation = menuBar.borderWidth / 2
                let scaleX = (adjustedBounds.width - menuBar.borderWidth) / adjustedBounds.width
                let scaleY = (adjustedBounds.height - menuBar.borderWidth) / adjustedBounds.height
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
