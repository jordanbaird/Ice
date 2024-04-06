//
//  MenuBarItemManager.swift
//  Ice
//

import Cocoa
import Combine

class MenuBarItemManager: ObservableObject {
    enum MenuBarItemError: Error {
        case noMenuBarWindow
    }
    private(set) weak var menuBarManager: MenuBarManager?

    init(menuBarManager: MenuBarManager) {
        self.menuBarManager = menuBarManager
    }

    // MARK: Menu Bar Items

    /// Returns an array of menu bar items in the given menu bar from the given windows.
    func getMenuBarItems(windows: [WindowInfo], menuBarWindow: WindowInfo, display: DisplayInfo) -> [MenuBarItem] {
        let items = windows.compactMap { window in
            MenuBarItem(itemWindow: window, menuBarWindow: menuBarWindow, display: display)
        }
        return items.sorted { lhs, rhs in
            lhs.frame.maxX < rhs.frame.maxX
        }
    }

    /// Returns an array of menu bar items in the menu bar for the given display.
    func getMenuBarItems(for display: DisplayInfo, onScreenOnly: Bool) throws -> [MenuBarItem] {
        let windows = try WindowInfo.getCurrent(option: onScreenOnly ? .optionOnScreenOnly : .optionAll)
        guard let menuBarWindow = WindowInfo.getMenuBarWindow(from: windows, for: display) else {
            throw MenuBarItemError.noMenuBarWindow
        }
        return getMenuBarItems(windows: windows, menuBarWindow: menuBarWindow, display: display)
    }

    /// Asynchronously returns an array of menu bar items in the menu bar for the given display.
    func menuBarItems(for display: DisplayInfo, onScreenOnly: Bool) async throws -> [MenuBarItem] {
        let windows = try await WindowInfo.current(option: onScreenOnly ? .optionOnScreenOnly : .optionAll)
        guard let menuBarWindow = WindowInfo.getMenuBarWindow(from: windows, for: display) else {
            throw MenuBarItemError.noMenuBarWindow
        }
        return getMenuBarItems(windows: windows, menuBarWindow: menuBarWindow, display: display)
    }
}
