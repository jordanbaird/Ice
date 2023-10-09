//
//  MenuBarItem.swift
//  Ice
//

import ScreenCaptureKit

/// An item in the menu bar.
struct MenuBarItem {
    /// The title of the Control Center menu bar item.
    private static let controlCenterWindowTitle: String = "BentoBox"

    /// The title of the Time Machine menu bar item.
    private static let timeMachineWindowTitle: String = {
        if ProcessInfo.processInfo.operatingSystemVersion.majorVersion >= 14 {
            "TimeMachine.TMMenuExtraHost"
        } else {
            "TMMenuExtra"
        }
    }()

    /// The window containing the menu bar item.
    let window: SCWindow

    /// An image representation of the menu bar item.
    let image: CGImage

    /// The menu bar item's title.
    var title: String {
        if let owningApplication = window.owningApplication {
            // we have an owning application; by default, use
            // its name, but handle a couple of special cases
            switch owningApplication.bundleIdentifier {
            case "com.apple.controlcenter":
                // icons such as Battery, WiFi, Bluetooth, etc.
                // are all owned by the Control Center process
                if window.title == Self.controlCenterWindowTitle {
                    // actual Control Center icon should use the
                    // application name
                    owningApplication.applicationName
                } else {
                    // default to window title for other icons
                    window.title ?? owningApplication.applicationName
                }
            case "com.apple.systemuiserver":
                if window.title == Self.timeMachineWindowTitle {
                    "Time Machine"
                } else {
                    window.title ?? owningApplication.applicationName
                }
            default:
                owningApplication.applicationName
            }
        } else if let title = window.title {
            // no owning application; default to window title
            title
        } else {
            // no owning application or window title; use empty
            // string as fallback
            String()
        }
    }

    /// A Boolean value indicating whether the menu bar item's
    /// window is on screen.
    var isOnScreen: Bool {
        window.isOnScreen
    }
}

// MARK: MenuBarItem: Equatable
extension MenuBarItem: Equatable {
    static func == (lhs: MenuBarItem, rhs: MenuBarItem) -> Bool {
        lhs.window == rhs.window &&
        lhs.image.dataProvider?.data == rhs.image.dataProvider?.data
    }
}

// MARK: MenuBarItem: Hashable
extension MenuBarItem: Hashable {
    func hash(into hasher: inout Hasher) {
        hasher.combine(window)
        hasher.combine(image.dataProvider?.data)
    }
}
