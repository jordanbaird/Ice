//
//  AccessibilityMenuBar.swift
//  Ice
//

import AXSwift
import Cocoa

/// An accessibility representation of a menu bar.
@MainActor
struct AccessibilityMenuBar {
    /// The underyling UI element.
    let uiElement: UIElement

    /// Creates an accessibility menu bar from the given UI element.
    ///
    /// - Parameter uiElement: A UI element that represents a menu bar.
    init(uiElement: UIElement) throws {
        do {
            guard try uiElement.role() == .menuBar else {
                throw AccessibilityError(message: "Not a menu bar")
            }
            self.uiElement = uiElement
        } catch let error as AccessibilityError {
            throw error
        } catch {
            throw AccessibilityError(message: "Invalid menu bar", underlyingError: error)
        }
    }

    /// Creates an accessibility menu bar for the given display.
    ///
    /// - Parameter display: The display to get the menu bar for.
    init(display: CGDirectDisplayID) async throws {
        do {
            let menuBarWindow: WindowInfo
            do {
                menuBarWindow = try await WindowInfo.menuBarWindow(for: display)
            } catch {
                throw AccessibilityError(message: "No menu bar window for display \(display)", underlyingError: error)
            }
            let position = menuBarWindow.frame.origin
            guard let uiElement = try systemWideElement.elementAtPosition(Float(position.x), Float(position.y)) else {
                throw AccessibilityError(message: "No menu bar at position \(position)")
            }
            try self.init(uiElement: uiElement)
        } catch let error as AccessibilityError {
            throw error
        } catch {
            throw AccessibilityError(message: "Invalid menu bar for display \(display)", underlyingError: error)
        }
    }

    /// Returns a Boolean value that indicates whether the given display
    /// has a valid menu bar.
    static func hasValidMenuBar(for display: CGDirectDisplayID) async -> Bool {
        do {
            let menuBarWindow = try await WindowInfo.menuBarWindow(for: display)
            let position = menuBarWindow.frame.origin
            let uiElement = try systemWideElement.elementAtPosition(Float(position.x), Float(position.y))
            return try uiElement?.role() == .menuBar
        } catch {
            return false
        }
    }

    /// Returns the menu bar's frame.
    func frame() throws -> CGRect {
        do {
            guard let frame: CGRect = try uiElement.attribute(.frame) else {
                throw AccessibilityError(message: "Missing frame")
            }
            return frame
        } catch let error as AccessibilityError {
            throw error
        } catch {
            throw AccessibilityError(message: "Invalid frame", underlyingError: error)
        }
    }

    /// Returns an array of the items in the menu bar.
    func menuBarItems() throws -> [AccessibilityMenuBarItem] {
        do {
            guard let children: [UIElement] = try uiElement.arrayAttribute(.children) else {
                throw AccessibilityError(message: "Missing menu bar items")
            }
            return try children.map { child in
                try AccessibilityMenuBarItem(uiElement: child)
            }
        } catch let error as AccessibilityError {
            throw error
        } catch {
            throw AccessibilityError(message: "Invalid menu bar items", underlyingError: error)
        }
    }
}
