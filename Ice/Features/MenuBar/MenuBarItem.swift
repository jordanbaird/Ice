//
//  MenuBarItem.swift
//  Ice
//

import ScreenCaptureKit

private func bestDisplayName(for window: SCWindow) -> String {
    guard let application = window.owningApplication else {
        return window.title ?? ""
    }
    guard let title = window.title else {
        return application.applicationName
    }
    // by default, use the application name, but handle some special cases
    return switch application.bundleIdentifier {
    case "com.apple.controlcenter":
        if title == "BentoBox" { // Control Center icon
            application.applicationName
        } else if title == "NowPlaying" {
            "Now Playing"
        } else {
            title
        }
    case "com.apple.systemuiserver":
        if title == "TimeMachine.TMMenuExtraHost" {
            "Time Machine"
        } else {
            title
        }
    default:
        application.applicationName
    }
}

/// An item in the menu bar.
class MenuBarItem {
    let displayName: String
    let frame: CGRect
    let isActive: Bool
    let isOnScreen: Bool
    let windowID: CGWindowID

    init(window: SCWindow) {
        self.displayName = bestDisplayName(for: window)
        self.frame = window.frame
        self.isActive = window.isActive
        self.isOnScreen = window.isOnScreen
        self.windowID = window.windowID
    }

    func captureImage(with content: SharedContent) -> CGImage? {
        guard
            let window = content.windows.first(where: { $0.windowID == windowID }),
            window.isOnScreen
        else {
            return nil
        }
        return WindowCaptureManager.captureImage(window: window, options: .ignoreFraming)
    }
}

// MARK: MenuBarItem: Equatable
extension MenuBarItem: Equatable {
    static func == (lhs: MenuBarItem, rhs: MenuBarItem) -> Bool {
        lhs.displayName == rhs.displayName &&
        lhs.frame.width == rhs.frame.width &&
        lhs.frame.height == rhs.frame.height &&
        lhs.frame.origin.x == rhs.frame.origin.x &&
        lhs.frame.origin.y == rhs.frame.origin.y &&
        lhs.isActive == rhs.isActive &&
        lhs.isOnScreen == rhs.isOnScreen &&
        lhs.windowID == rhs.windowID
    }
}

// MARK: MenuBarItem: Hashable
extension MenuBarItem: Hashable {
    func hash(into hasher: inout Hasher) {
        hasher.combine(displayName)
        hasher.combine(frame.width)
        hasher.combine(frame.height)
        hasher.combine(frame.origin.x)
        hasher.combine(frame.origin.y)
        hasher.combine(isActive)
        hasher.combine(isOnScreen)
        hasher.combine(windowID)
    }
}
