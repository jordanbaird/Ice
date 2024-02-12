//
//  MenuBarBackingPanel.swift
//  Ice
//

import Cocoa
import Combine

// MARK: - MenuBarBackingPanel

class MenuBarBackingPanel: MenuBarAppearancePanel_Old {
    private var cancellables = Set<AnyCancellable>()

    init(appearanceManager: MenuBarAppearanceManager) {
        super.init(level: Level(Int(CGWindowLevelForKey(.desktopIconWindow))), appearanceManager: appearanceManager)
        self.contentView = MenuBarBackingPanelView(appearanceManager: appearanceManager)
    }

    func configureCancellables() {
        var c = Set<AnyCancellable>()

        if let appearanceManager {
            Publishers.CombineLatest3(
                appearanceManager.$hasShadow,
                appearanceManager.$hasBorder,
                appearanceManager.$shapeKind
            )
            .map { hasShadow, hasBorder, shapeKind in
                guard shapeKind == .none else {
                    return false
                }
                return hasShadow || hasBorder
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
        let offset: CGFloat = {
            guard
                let appearanceManager,
                appearanceManager.hasBorder
            else {
                return 0
            }
            return appearanceManager.borderWidth
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
    private weak var appearanceManager: MenuBarAppearanceManager?
    private var cancellables = Set<AnyCancellable>()

    init(appearanceManager: MenuBarAppearanceManager) {
        super.init(frame: .zero)
        self.appearanceManager = appearanceManager
        configureCancellables()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private func configureCancellables() {
        var c = Set<AnyCancellable>()

        if let appearanceManager {
            Publishers.CombineLatest4(
                appearanceManager.$hasShadow,
                appearanceManager.$hasBorder,
                appearanceManager.$borderColor,
                appearanceManager.$borderWidth
            )
            .combineLatest(appearanceManager.$shapeKind)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.needsDisplay = true
            }
            .store(in: &c)
        }

        cancellables = c
    }

    override func draw(_ dirtyRect: NSRect) {
        guard let appearanceManager else {
            return
        }

        if appearanceManager.hasShadow {
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

        if appearanceManager.hasBorder {
            let borderBounds = CGRect(
                x: bounds.minX,
                y: bounds.minY + 5,
                width: bounds.width,
                height: appearanceManager.borderWidth
            )
            NSColor(cgColor: appearanceManager.borderColor)?.setFill()
            NSBezierPath(rect: borderBounds).fill()
        }
    }
}
