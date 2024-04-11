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
}

// MARK: - Menu Bar Items

extension MenuBarItemManager {

    // MARK: Sync

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
        let windows = if onScreenOnly {
            try WindowInfo.getOnScreenWindows(excludeDesktopWindows: true)
        } else {
            try WindowInfo.getAllWindows(excludeDesktopWindows: true)
        }
        let menuBarWindow = try WindowInfo.getMenuBarWindow(from: windows, for: display)
        return getMenuBarItems(windows: windows, menuBarWindow: menuBarWindow, display: display)
    }

    // MARK: Async

    /// Asynchronously returns an array of menu bar items in the given menu bar from the given windows.
    func menuBarItems(windows: [WindowInfo], menuBarWindow: WindowInfo, display: DisplayInfo) async throws -> [MenuBarItem] {
        var items = [MenuBarItem]()

        for window in windows {
            try Task.checkCancellation()
            await Task.yield()
            if let item = MenuBarItem(itemWindow: window, menuBarWindow: menuBarWindow, display: display) {
                items.append(item)
            }
        }

        try Task.checkCancellation()
        await Task.yield()

        items.sort { lhs, rhs in
            lhs.frame.maxX < rhs.frame.maxX
        }

        return items
    }

    /// Asynchronously returns an array of menu bar items in the menu bar for the given display.
    func menuBarItems(for display: DisplayInfo, onScreenOnly: Bool) async throws -> [MenuBarItem] {
        let windows = if onScreenOnly {
            try await WindowInfo.onScreenWindows(excludeDesktopWindows: true)
        } else {
            try await WindowInfo.allWindows(excludeDesktopWindows: true)
        }
        let menuBarWindow = try await WindowInfo.menuBarWindow(from: windows, for: display)
        return try await menuBarItems(windows: windows, menuBarWindow: menuBarWindow, display: display)
    }
}
