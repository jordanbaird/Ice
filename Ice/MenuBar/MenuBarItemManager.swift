//
//  MenuBarItemManager.swift
//  Ice
//

import Cocoa
import Combine
import ScreenCaptureKit

class MenuBarItemManager: ObservableObject {
    private(set) weak var menuBarManager: MenuBarManager?

    init(menuBarManager: MenuBarManager) {
        self.menuBarManager = menuBarManager
    }

    /// Returns an array of menu bar items in the menu bar of the given display.
    func getMenuBarItems(for display: SCDisplay, onScreenOnly: Bool) -> [MenuBarItem] {
        let menuBarWindowPredicate: (WindowInfo) -> Bool = { window in
            window.isOnScreen &&
            display.frame.contains(window.frame) &&
            window.owningApplication == nil &&
            window.windowLayer == kCGMainMenuWindowLevel &&
            window.title == "Menubar"
        }

        let windows = WindowInfo.getCurrent(option: onScreenOnly ? .optionOnScreenOnly : .optionAll)

        guard let menuBarWindow = windows.first(where: menuBarWindowPredicate) else {
            return []
        }

        return windows.compactMap { window in
            MenuBarItem(itemWindow: window, menuBarWindow: menuBarWindow, display: display)
        }
    }
}
