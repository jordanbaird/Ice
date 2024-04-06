//
//  AccessibilityApplication.swift
//  Ice
//

import AXSwift
import Cocoa

/// An accessibility representation of an application.
struct AccessibilityApplication {
    let application: Application

    /// Creates an accessibility application from an application retrieved
    /// from an accessibility framework.
    init(application: Application) {
        self.application = application
    }

    /// Creates an accessibility application from a running application.
    init(_ runningApplication: NSRunningApplication) throws {
        guard let application = Application(runningApplication) else {
            throw AccessibilityError(message: "Could not create application")
        }
        self.init(application: application)
    }

    func menuBar() throws -> AccessibilityMenuBar {
        do {
            guard let uiElement: UIElement = try application.attribute(.menuBar) else {
                throw AccessibilityError(message: "No menu bar for application")
            }
            return try AccessibilityMenuBar(uiElement: uiElement)
        } catch let error as AccessibilityError {
            throw error
        } catch {
            throw AccessibilityError(message: "Invalid menu bar for application", underlyingError: error)
        }
    }
}
