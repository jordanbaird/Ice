//
//  NSScreen+getMenuBarHeight.swift
//  Ice
//

import Cocoa

extension NSScreen {
    /// Returns the height of the menu bar on this screen.
    func getMenuBarHeight() -> CGFloat? {
        let menuBarWindow = WindowInfo.getMenuBarWindow(for: displayID)
        return menuBarWindow?.frame.height
    }
}
