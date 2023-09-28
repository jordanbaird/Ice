//
//  MenuBarItemManager.swift
//  Ice
//

import Combine
import ScreenCaptureKit

/// Constants that represent the titles of windows.
private enum WindowTitles {
    /// The title of the Control Center menu bar item.
    static let controlCenter: String = "BentoBox"

    /// The title of the menu bar.
    static let menuBar: String = "Menubar"

    /// The title of the Time Machine menu bar item.
    static let timeMachine: String = {
        if ProcessInfo.processInfo.operatingSystemVersion.majorVersion >= 14 {
            "TimeMachine.TMMenuExtraHost"
        } else {
            "TMMenuExtra"
        }
    }()
}

/// An item in a menu bar.
struct MenuBarItem: Hashable {
    /// The window containing the menu bar item.
    let window: SCWindow

    /// The menu bar item's title.
    var title: String {
        if let owningApplication = window.owningApplication {
            // we have an owning application; by default, use
            // its name, but handle a couple of special cases
            switch owningApplication.bundleIdentifier {
            case "com.apple.controlcenter":
                // icons such as Battery, WiFi, Bluetooth, etc.
                // are all owned by the Control Center process
                if window.title == WindowTitles.controlCenter {
                    // actual Control Center icon should use the
                    // application name
                    owningApplication.applicationName
                } else {
                    // default to window title for other icons
                    window.title ?? owningApplication.applicationName
                }
            case "com.apple.systemuiserver":
                if window.title == WindowTitles.timeMachine {
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

    init(window: SCWindow) {
        self.window = window
    }
}

class MenuBarItemManager: ObservableObject {
    private var cancellables = Set<AnyCancellable>()

    private(set) weak var menuBar: MenuBar?

    @Published var items = [MenuBarItem]()

    init(menuBar: MenuBar) {
        self.menuBar = menuBar
        configureCancellables()
    }

    func activate() {
        updateMenuBarItems(windows: WindowList.shared.windows)
        configureCancellables()
    }

    func deactivate() {
        cancellables.removeAll()
        items.removeAll()
    }

    /// Sets up a series of cancellables to respond to important
    /// changes in the menu bar item manager's state.
    private func configureCancellables() {
        var c = Set<AnyCancellable>()

        WindowList.shared.$windows
            .receive(on: RunLoop.main)
            .sink { [weak self] windows in
                self?.updateMenuBarItems(windows: windows)
            }
            .store(in: &c)

        cancellables = c
    }

    private func updateMenuBarItems(windows: [SCWindow]) {
        let menuBarWindow = windows.first { window in
            self.windowIsMenuBar(window)
        }
        guard let menuBarWindow else {
            // TODO: log the error
            return
        }
        items = windows
            .filter { window in
                self.windowIsMenuBarItem(window, in: menuBarWindow) &&
                !self.windowIsControlItem(window, in: menuBarWindow)
            }
            .sorted { first, second in
                first.frame.minX < second.frame.minX
            }
            .map { window in
                MenuBarItem(window: window)
            }
    }

    /// Returns a Boolean value indicating whether the given window
    /// is a menu bar.
    private func windowIsMenuBar(_ window: SCWindow) -> Bool {
        window.windowLayer == kCGMainMenuWindowLevel &&
        window.title == WindowTitles.menuBar
    }

    /// Returns a Boolean value indicating whether the given window
    /// is a menu bar item within the given menu bar window.
    ///
    /// - Parameters:
    ///   - window: The window to check.
    ///   - menuBarWindow: A window to treat as a menu bar when determining
    ///     if `window` is one of its items. This window must return `true`
    ///     when passed to a call to ``windowIsMenuBar(_:)``.
    private func windowIsMenuBarItem(_ window: SCWindow, in menuBarWindow: SCWindow) -> Bool {
        windowIsMenuBar(menuBarWindow) &&
        window.windowLayer == kCGStatusWindowLevel &&
        window.frame.height == menuBarWindow.frame.height
    }

    /// Returns a Boolean value indicating whether the given window
    /// is a control item.
    private func windowIsControlItem(_ window: SCWindow, in menuBarWindow: SCWindow) -> Bool {
        guard
            windowIsMenuBarItem(window, in: menuBarWindow),
            window.owningApplication?.processID == ProcessInfo.processInfo.processIdentifier,
            let menuBar
        else {
            return false
        }
        return menuBar.sections.contains { section in
            section.controlItem.autosaveName == window.title
        }
    }
}
