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

    /// Returns an array of windows belonging to the on-screen
    /// menu bar items in the menu bar for the given display.
    func getOnScreenMenuBarItemWindows(for display: SCDisplay) -> [WindowInfo] {
        let menuBarWindowPredicate: (WindowInfo) -> Bool = { window in
            display.frame.contains(window.frame) &&
            // menu bar window belongs to the WindowServer process
            // (identified by a `nil` owningApplication)
            window.owningApplication == nil &&
            window.windowLayer == kCGMainMenuWindowLevel &&
            window.title == "Menubar"
        }

        let windows = WindowInfo.getCurrent(option: .optionOnScreenOnly)

        guard let menuBarWindow = windows.first(where: menuBarWindowPredicate) else {
            return []
        }

        return windows
            .filter { window in
                // must have status window level
                window.windowLayer == kCGStatusWindowLevel &&
                // must fit vertically inside menu bar window
                window.frame.minY == menuBarWindow.frame.minY &&
                window.frame.maxY == menuBarWindow.frame.maxY
            }
            .sorted { first, second in
                first.frame.minX < second.frame.minX
            }
    }
}
