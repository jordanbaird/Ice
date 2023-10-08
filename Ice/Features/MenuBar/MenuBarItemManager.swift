//
//  MenuBarItemManager.swift
//  Ice
//

import Combine
import ScreenCaptureKit

class MenuBarItemManager: ObservableObject {
    private var cancellables = Set<AnyCancellable>()

    private(set) weak var menuBar: MenuBar?

    @Published var alwaysVisibleItems = [MenuBarItem]()
    @Published var hiddenItems = [MenuBarItem]()
    @Published var alwaysHiddenItems = [MenuBarItem]()

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
        alwaysVisibleItems.removeAll()
        hiddenItems.removeAll()
        alwaysHiddenItems.removeAll()
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
        guard
            let menuBar,
            let menuBarWindow = windows.first(where: windowIsMenuBar),
            let alwaysVisibleSection = menuBar.section(withName: .alwaysVisible),
            let hiddenSection = menuBar.section(withName: .hidden)
        else {
            return
        }
        let sortedWindows = windows
            .filter { window in
                self.windowIsMenuBarItem(window, in: menuBarWindow) &&
                !self.windowIsControlItem(window, in: menuBarWindow)
            }
            .sorted { first, second in
                first.frame.minX < second.frame.minX
            }
        alwaysVisibleItems = sortedWindows
            .filter { window in
                window.frame.midX > (hiddenSection.controlItem.windowFrame?.midX ?? 0) &&
                window.windowID != alwaysVisibleSection.controlItem.windowID
            }
            .map { window in
                MenuBarItem(window: window)
            }
        if let alwaysHiddenSection = menuBar.section(withName: .alwaysHidden) {
            if alwaysHiddenSection.isEnabled {
                hiddenItems = sortedWindows
                    .filter { window in
                        window.frame.midX < (hiddenSection.controlItem.windowFrame?.midX ?? 0) &&
                        window.frame.midX > (alwaysHiddenSection.controlItem.windowFrame?.midX ?? 0) &&
                        window.windowID != hiddenSection.controlItem.windowID &&
                        window.windowID != alwaysHiddenSection.controlItem.windowID
                    }
                    .map { window in
                        MenuBarItem(window: window)
                    }
                alwaysHiddenItems = sortedWindows
                    .filter { window in
                        window.frame.midX < (alwaysHiddenSection.controlItem.windowFrame?.midX ?? 0) &&
                        window.windowID != alwaysHiddenSection.controlItem.windowID
                    }
                    .map { window in
                        MenuBarItem(window: window)
                    }
            } else {
                hiddenItems = sortedWindows
                    .filter { window in
                        window.frame.midX < (hiddenSection.controlItem.windowFrame?.midX ?? 0) &&
                        window.windowID != hiddenSection.controlItem.windowID
                    }
                    .map { window in
                        MenuBarItem(window: window)
                    }
            }
        }
    }

    /// Returns a Boolean value indicating whether the given window
    /// is a menu bar.
    private func windowIsMenuBar(_ window: SCWindow) -> Bool {
        window.windowLayer == kCGMainMenuWindowLevel &&
        window.title == "Menubar"
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
