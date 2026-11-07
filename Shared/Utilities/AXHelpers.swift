//
//  AXHelpers.swift
//  Shared
//

import AXSwift
import Cocoa

enum AXHelpers {
    /// Invariant: ``queue`` is *concurrent* and does not serialize anything by
    /// itself. It only moves the (potentially slow) Accessibility calls off the
    /// caller's thread. Everything run on it must be a thread-safe, read-only AX
    /// query (hit-testing, attribute reads, trust checks); nothing here mutates
    /// shared state. Don't add AX writes or non-thread-safe state to it without
    /// making it serial.
    ///
    /// The system-wide element, used only from within ``queue``. (AXSwift's own
    /// `systemWideElement` global is mutable shared state; this is our own.)
    private nonisolated(unsafe) static let systemWide = AXUIElementCreateSystemWide()

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
        queue.sync {
            var element: AXUIElement?
            let error = AXUIElementCopyElementAtPosition(systemWide, Float(point.x), Float(point.y), &element)
            guard error == .success, let element else {
                return nil
            }
            return UIElement(element)
        }
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
}
