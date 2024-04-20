//
//  MenuBarItem.swift
//  Ice
//

import Cocoa

/// A type that represents an item in a menu bar.
struct MenuBarItem {
    let windowID: CGWindowID
    let frame: CGRect
    let title: String?
    let owningApplication: NSRunningApplication?
    let isOnScreen: Bool

    /// Creates a menu bar item.
    ///
    /// The parameters passed into this initializer are verified during the menu
    /// bar item's creation. If `itemWindow` does not represent a menu bar item
    /// in the menu bar represented by `menuBarWindow`, and if `menuBarWindow`
    /// does not represent a menu bar on the display represented by `display`,
    /// the initializer will fail.
    ///
    /// - Parameters:
    ///   - itemWindow: A window that contains information about the item.
    ///   - menuBarWindow: A window that contains information about the item's menu bar.
    ///   - display: The display that contains the item's menu bar.
    init?(itemWindow: WindowInfo, menuBarWindow: WindowInfo, display: DisplayInfo) {
        // verify menuBarWindow
        guard Predicates.menuBarWindow(for: display)(menuBarWindow) else {
            return nil
        }

        // verify itemWindow
        guard
            itemWindow.windowLayer == kCGStatusWindowLevel,
            itemWindow.frame.minY == menuBarWindow.frame.minY,
            itemWindow.frame.maxY == menuBarWindow.frame.maxY
        else {
            return nil
        }

        self.windowID = itemWindow.windowID
        self.frame = itemWindow.frame
        self.title = itemWindow.title
        self.owningApplication = itemWindow.owningApplication
        self.isOnScreen = itemWindow.isOnScreen
    }
}
