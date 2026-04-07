//
//  AXHelpers.swift
//  Shared
//

import AXSwift
import Cocoa

enum AXHelpers {
    private static let queue = DispatchQueue.targetingGlobal(
        label: "AXHelpers.queue",
        qos: .userInteractive,
        attributes: .concurrent
    )

    @discardableResult
    static func isProcessTrusted(prompt: Bool = false) -> Bool {
        queue.sync { checkIsProcessTrusted(prompt: prompt) }
    }

    static func element(at point: CGPoint) -> UIElement? {
        queue.sync { try? systemWideElement.elementAtPosition(Float(point.x), Float(point.y)) }
    }

    static func application(for runningApp: NSRunningApplication) -> Application? {
        queue.sync { Application(runningApp) }
    }

    static func extrasMenuBar(for app: Application) -> UIElement? {
        queue.sync { try? app.attribute(.extrasMenuBar) }
    }

    static func children(for element: UIElement) -> [UIElement] {
        queue.sync { try? element.arrayAttribute(.children) } ?? []
    }

    static func isEnabled(_ element: UIElement) -> Bool {
        queue.sync { try? element.attribute(.enabled) } ?? false
    }

    static func frame(for element: UIElement) -> CGRect? {
        queue.sync { try? element.attribute(.frame) }
    }

    static func role(for element: UIElement) -> Role? {
        queue.sync { try? element.role() }
    }

    static func parent(of element: UIElement) -> UIElement? {
        queue.sync { try? element.attribute(.parent) }
    }

    /// Returns the menu bar AX element near the given display origin, by
    /// hit-testing a few points along the leftmost portion of the menu
    /// bar and walking up the AX parent chain when a hit lands inside a
    /// menu bar item.
    ///
    /// Querying the very corner pixel (`displayOrigin`) is unreliable in
    /// several configurations:
    ///
    ///   * On notched Apple silicon Macs the corner pixel falls outside
    ///     the screen's rounded-corner mask, so the hit-test returns nil.
    ///   * Menu bar accessories that paint near the corner (e.g. NotchNook)
    ///     can intercept the hit-test and return their own AX element.
    ///   * On macOS 26 the more transparent ("Liquid Glass") menu bar can
    ///     classify the topmost edge as the underlying window in some
    ///     foreground apps, again returning a non-menu-bar element.
    ///
    /// The probe offsets target the Apple-menu / app-menu region on the
    /// left side of the bar, which is well clear of the notch and any
    /// centred menu bar accessories.
    static func menuBarElement(nearDisplayOrigin displayOrigin: CGPoint) -> UIElement? {
        let probeOffsets: [CGPoint] = [
            CGPoint(x: 5, y: 12),
            CGPoint(x: 40, y: 12),
            CGPoint(x: 80, y: 12),
            CGPoint(x: 0, y: 0),
        ]

        for offset in probeOffsets {
            let point = CGPoint(
                x: displayOrigin.x + offset.x,
                y: displayOrigin.y + offset.y
            )
            guard var element = element(at: point) else {
                continue
            }
            // Walk up at most a handful of parents looking for the menu bar.
            // The hit normally lands on either the menu bar itself or one of
            // its direct menu bar item children, so 4 hops is plenty.
            for _ in 0..<4 {
                if role(for: element) == .menuBar {
                    return element
                }
                guard let next = parent(of: element) else {
                    break
                }
                element = next
            }
        }

        return nil
    }
}
