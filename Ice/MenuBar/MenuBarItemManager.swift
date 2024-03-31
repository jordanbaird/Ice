//
//  MenuBarItemManager.swift
//  Ice
//

import Cocoa
import Combine

class MenuBarItemManager: ObservableObject {
    private(set) weak var menuBarManager: MenuBarManager?

    init(menuBarManager: MenuBarManager) {
        self.menuBarManager = menuBarManager
    }

    /// Returns the first menu bar window from the given array of windows
    /// for the given display.
    func getMenuBarWindow(from windows: [WindowInfo], for display: DisplayInfo) -> WindowInfo? {
        windows.first { window in
            window.isOnScreen &&
            display.frame.contains(window.frame) &&
            window.owningApplication == nil &&
            window.windowLayer == kCGMainMenuWindowLevel &&
            window.title == "Menubar"
        }
    }

    /// Returns the first menu bar window for the given display.
    func getMenuBarWindow(for display: DisplayInfo) -> WindowInfo? {
        let windows = WindowInfo.getCurrent(option: .optionOnScreenOnly)
        return getMenuBarWindow(from: windows, for: display)
    }

    /// Returns an array of menu bar items in the given menu bar from the given windows.
    func getMenuBarItems(windows: [WindowInfo], menuBarWindow: WindowInfo, display: DisplayInfo) -> [MenuBarItem] {
        let items = windows.compactMap { window in
            MenuBarItem(itemWindow: window, menuBarWindow: menuBarWindow, display: display)
        }
        return items.sorted { lhs, rhs in
            lhs.frame.maxX < rhs.frame.maxX
        }
    }

    /// Returns an array of menu bar items in the menu bar of the given display.
    func getMenuBarItems(for display: DisplayInfo, onScreenOnly: Bool) -> [MenuBarItem] {
        let windows = WindowInfo.getCurrent(option: onScreenOnly ? .optionOnScreenOnly : .optionAll)
        guard let menuBarWindow = getMenuBarWindow(from: windows, for: display) else {
            return []
        }
        return getMenuBarItems(windows: windows, menuBarWindow: menuBarWindow, display: display)
    }
}
