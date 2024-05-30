//
//  MenuBarItemManager.swift
//  Ice
//

import Combine
import CoreGraphics

class MenuBarItemManager: ObservableObject {
    private(set) weak var appState: AppState?

    init(appState: AppState) {
        self.appState = appState
    }
}

// MARK: - Menu Bar Items

extension MenuBarItemManager {
    /// Returns an array of menu bar items in the given menu bar from the given windows.
    func getMenuBarItems(windows: [WindowInfo], menuBarWindow: WindowInfo, display: CGDirectDisplayID) -> [MenuBarItem] {
        let items = windows.compactMap { window in
            MenuBarItem(itemWindow: window, menuBarWindow: menuBarWindow, display: display)
        }
        return items.sorted { lhs, rhs in
            lhs.frame.maxX < rhs.frame.maxX
        }
    }

    /// Returns an array of menu bar items in the menu bar for the given display.
    func getMenuBarItems(for display: CGDirectDisplayID, onScreenOnly: Bool) throws -> [MenuBarItem] {
        let windows = if onScreenOnly {
            try WindowInfo.getOnScreenWindows(excludeDesktopWindows: true)
        } else {
            try WindowInfo.getAllWindows(excludeDesktopWindows: true)
        }
        let menuBarWindow = try WindowInfo.getMenuBarWindow(from: windows, for: display)
        return getMenuBarItems(windows: windows, menuBarWindow: menuBarWindow, display: display)
    }
}
