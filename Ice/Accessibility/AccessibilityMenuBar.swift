//
//  AccessibilityMenuBar.swift
//  Ice
//

import AXSwift

/// An accessibility representation of a menu bar.
struct AccessibilityMenuBar {
    /// The underyling UI element.
    let uiElement: UIElement

    /// Creates an accessibility menu bar from the given UI element.
    /// 
    /// This initializer throws an error if the provided UI element is not a menu bar.
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
