//
//  ScreenBottomCornerOverlayPanel.swift
//  Ice
//

import Cocoa

/// A panel that draws solid-black wedges at the bottom-left and bottom-right
/// of its owning screen, simulating rounded screen bottom corners.
final class ScreenBottomCornerOverlayPanel: NSPanel {
    private(set) weak var appState: AppState?

    /// The screen that owns the panel.
    let owningScreen: NSScreen

    init(appState: AppState, owningScreen: NSScreen) {
        self.appState = appState
        self.owningScreen = owningScreen
        super.init(
            contentRect: .zero,
            styleMask: [.borderless, .fullSizeContentView, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        self.level = .statusBar
        self.title = "Screen Bottom Corner Overlay"
        self.backgroundColor = .clear
        self.hasShadow = false
        self.ignoresMouseEvents = true
        // `.canJoinAllSpaces` puts the panel on every desktop space, and
        // `.fullScreenAuxiliary` allows it on fullscreen-app spaces too;
        // `updateVisibility()` then orders the panel out when the per-screen
        // settings say it should be hidden in the current space.
        self.collectionBehavior = [.ignoresCycle, .canJoinAllSpaces, .stationary, .fullScreenAuxiliary]
        self.contentView = ScreenBottomCornerOverlayPanelContentView()
    }

    /// Positions the panel along the bottom edge of the owning screen and
    /// orders it to the front (if visibility conditions allow).
    func show() {
        guard
            let appState,
            !appState.isPreview
        else {
            return
        }

        let info = appState.appearanceManager.configuration.effectiveScreenShapeInfo(for: owningScreen)
        let radius = info.cornerRadius
        let newFrame = CGRect(
            x: owningScreen.frame.minX,
            y: owningScreen.frame.minY,
            width: owningScreen.frame.width,
            height: radius
        )
        setFrame(newFrame, display: false)
        contentView?.needsDisplay = true
        updateVisibility()
    }

    /// Brings the panel to the front when its settings allow it to be
    /// visible, or orders it out otherwise.
    func updateVisibility() {
        guard let appState else {
            return
        }
        let info = appState.appearanceManager.configuration.effectiveScreenShapeInfo(for: owningScreen)
        let isFullscreen = appState.menuBarManager.isSpaceFullscreen(on: owningScreen)
        let shouldShow = info.hasRoundedBottomCorners
            && (info.showInFullscreen || !isFullscreen)
        if shouldShow {
            orderFrontRegardless()
        } else {
            orderOut(nil)
        }
    }

    override func isAccessibilityElement() -> Bool {
        return false
    }
}

// MARK: - Content View

private final class ScreenBottomCornerOverlayPanelContentView: NSView {
    private var overlayPanel: ScreenBottomCornerOverlayPanel? {
        window as? ScreenBottomCornerOverlayPanel
    }

    override func draw(_ dirtyRect: NSRect) {
        guard
            let overlayPanel,
            let appState = overlayPanel.appState
        else {
            return
        }

        let info = appState.appearanceManager.configuration.effectiveScreenShapeInfo(for: overlayPanel.owningScreen)
        let radius = info.cornerRadius
        guard radius > 0 else {
            return
        }
        let width = bounds.width

        let leftPath = NSBezierPath()
        leftPath.move(to: CGPoint(x: 0, y: 0))
        leftPath.line(to: CGPoint(x: radius, y: 0))
        leftPath.appendArc(
            withCenter: CGPoint(x: radius, y: radius),
            radius: radius,
            startAngle: 270,
            endAngle: 180,
            clockwise: true
        )
        leftPath.close()

        let rightPath = NSBezierPath()
        rightPath.move(to: CGPoint(x: width, y: radius))
        rightPath.line(to: CGPoint(x: width, y: 0))
        rightPath.line(to: CGPoint(x: width - radius, y: 0))
        rightPath.appendArc(
            withCenter: CGPoint(x: width - radius, y: radius),
            radius: radius,
            startAngle: 270,
            endAngle: 0,
            clockwise: false
        )
        rightPath.close()

        NSColor.black.setFill()
        leftPath.fill()
        rightPath.fill()
    }
}
