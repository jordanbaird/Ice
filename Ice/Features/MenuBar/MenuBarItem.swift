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
struct MenuBarItem {
    let displayName: String
    let frame: CGRect
    let image: CGImage
    let isActive: Bool
    let isOnScreen: Bool
    let windowID: CGWindowID

    init?(window: SCWindow) {
        guard let image = WindowCaptureManager.captureImage(window: window, options: .ignoreFraming) else {
            return nil
        }
        self.displayName = bestDisplayName(for: window)
        self.frame = window.frame
        self.image = image
        self.isActive = window.isActive
        self.isOnScreen = window.isOnScreen
        self.windowID = window.windowID
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
        lhs.image.dataProvider?.data == rhs.image.dataProvider?.data &&
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
        hasher.combine(image.dataProvider?.data)
        hasher.combine(isActive)
        hasher.combine(isOnScreen)
        hasher.combine(windowID)
    }
}
