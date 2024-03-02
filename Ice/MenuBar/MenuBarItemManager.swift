//
//  MenuBarItemManager.swift
//  Ice
//

import Combine
import CoreGraphics

class MenuBarItemManager: ObservableObject {
    /// Returns an array of the windows belonging to the
    /// on-screen items in the menu bar.
    func getOnScreenMenuBarItemWindows() -> [WindowInfo] {
        let menuBarWindowPredicate: (WindowInfo) -> Bool = { window in
            // menu bar window belongs to the WindowServer process
            // (identified by a `nil` owningApplication)
            window.owningApplication == nil &&
            window.windowLayer == kCGMainMenuWindowLevel &&
            window.title == "Menubar"
        }

        let windows = WindowInfo.getCurrent(option: .optionOnScreenOnly)

        guard let menuBarWindow = windows.first(where: menuBarWindowPredicate) else {
            print("NONE")
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
