//
//  AXHelpers.swift
//  Shared
//

import AXSwift
import Cocoa

enum AXHelpers {
    /// How long an Accessibility message waits for a reply, in seconds.
    ///
    /// The system default is 6 seconds, and the calls here are synchronous, so an app
    /// that stops answering would hold the calling thread (often the main thread) that
    /// long. Elements that set their own timeout keep it.
    private static let messagingTimeout: Float = 1.0

    private static let queue: DispatchQueue = {
        // Every helper goes through the queue, so the global timeout is in place
        // before the first message is sent.
        UIElement.globalMessagingTimeout = messagingTimeout
        return DispatchQueue.targetingGlobal(
            label: "AXHelpers.queue",
            qos: .userInteractive,
            attributes: .concurrent
        )
    }()

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

    /// Returns the menu bar that holds the application menus, found at the
    /// given point before macOS 27.
    ///
    /// On macOS 27 the element at a display's origin is MenuBarAgent's window,
    /// so the menu bar comes from the application that owns it. Ice's own menus
    /// are skipped there: asking our own process from the main thread would wait
    /// for the main thread itself.
    static func applicationMenuBar(at point: CGPoint) -> UIElement? {
        if #available(macOS 27.0, *) {
            guard
                let owner = NSWorkspace.shared.menuBarOwningApplication,
                owner.processIdentifier != ProcessInfo.processInfo.processIdentifier,
                let app = application(for: owner)
            else {
                return nil
            }
            return queue.sync { try? app.attribute(.menuBar) }
        }
        guard let element = element(at: point), role(for: element) == .menuBar else {
            return nil
        }
        return element
    }
}
