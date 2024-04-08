//
//  AccessibilityMenuBarItem.swift
//  Ice
//

import AXSwift
import CoreGraphics

/// An accessibility representation of an item in a menu bar.
@MainActor
struct AccessibilityMenuBarItem {
    /// The underyling UI element.
    let uiElement: UIElement

    /// Creates an accessibility menu bar item from the given UI element.
    ///
    /// - Parameter uiElement: A UI element that represents a menu bar item.
    init(uiElement: UIElement) throws {
        do {
            guard let parent: UIElement = try uiElement.attribute(.parent) else {
                throw AccessibilityError(message: "Missing parent")
            }
            guard try parent.role() == .menuBar else {
                throw AccessibilityError(message: "Not a menu bar item")
            }
            self.uiElement = uiElement
        } catch let error as AccessibilityError {
            throw error
        } catch {
            throw AccessibilityError(message: "Invalid menu bar item", underlyingError: error)
        }
    }

    /// Returns the item's frame.
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
}
