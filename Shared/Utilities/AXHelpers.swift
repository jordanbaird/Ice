//
//  AXHelpers.swift
//  Shared
//

@preconcurrency import AXSwift
import Cocoa

enum AXHelpers {
    /// HIServices' AX value serializer can crash when this process performs an
    /// outgoing accessibility read on a background queue while its main thread
    /// is simultaneously answering another client's hierarchy request. Route
    /// every AX call through the main thread so incoming and outgoing
    /// serialization cannot overlap inside Ice. Callers doing a long walk can
    /// batch related reads with this helper to avoid one dispatch per value.
    static func performOnMain<T>(_ operation: () throws -> T) rethrows -> T {
        if Thread.isMainThread {
            return try operation()
        }
        return try DispatchQueue.main.sync(execute: operation)
    }

    /// Child AX elements do not inherit a timeout set on an application's
    /// root element. Configure the process-wide fallback once so a child that
    /// disappears while MenuBarAgent is recomposing cannot block the serialized
    /// scan for the Accessibility API's multi-second default timeout.
    private static let globalMessagingTimeoutConfiguration: Void = {
        AXUIElementSetMessagingTimeout(systemWideElement.element, 0.25)
    }()

    @discardableResult
    static func isProcessTrusted(prompt: Bool = false) -> Bool {
        performOnMain { checkIsProcessTrusted(prompt: prompt) }
    }

    static func element(at point: CGPoint) -> UIElement? {
        performOnMain {
            _ = globalMessagingTimeoutConfiguration
            return try? systemWideElement.elementAtPosition(Float(point.x), Float(point.y))
        }
    }

    static func application(for runningApp: NSRunningApplication) -> Application? {
        performOnMain {
            _ = globalMessagingTimeoutConfiguration
            let application = Application(runningApp)
            if let application {
                // A stalled application's accessibility server must not block
                // the complete menu bar scan indefinitely.
                AXUIElementSetMessagingTimeout(application.element, 0.25)
            }
            return application
        }
    }

    static func extrasMenuBar(for app: Application) -> UIElement? {
        performOnMain { try? app.attribute(.extrasMenuBar) }
    }

    static func children(for element: UIElement) -> [UIElement] {
        performOnMain { try? element.arrayAttribute(.children) } ?? []
    }

    static func isEnabled(_ element: UIElement) -> Bool {
        performOnMain { try? element.attribute(.enabled) } ?? false
    }

    static func frame(for element: UIElement) -> CGRect? {
        performOnMain { try? element.attribute(.frame) }
    }

    static func role(for element: UIElement) -> Role? {
        performOnMain { try? element.role() }
    }

    static func title(for element: UIElement) -> String? {
        performOnMain { try? element.attribute(.title) }
    }

    static func identifier(for element: UIElement) -> String? {
        performOnMain { try? element.attribute(.identifier) }
    }

    static func description(for element: UIElement) -> String? {
        performOnMain { try? element.attribute(.description) }
    }

    static func help(for element: UIElement) -> String? {
        performOnMain { try? element.attribute(.help) }
    }

    static func value(for element: UIElement) -> String? {
        performOnMain {
            let value: Any? = try? element.attribute(.value)
            return value as? String
        }
    }

    static func pid(for element: UIElement) -> pid_t? {
        performOnMain {
            var pid: pid_t = 0
            return AXUIElementGetPid(element.element, &pid) == .success ? pid : nil
        }
    }

    @discardableResult
    static func press(_ element: UIElement) -> Bool {
        performOnMain {
            do {
                try element.performAction(.press)
                return true
            } catch {
                return false
            }
        }
    }
}
