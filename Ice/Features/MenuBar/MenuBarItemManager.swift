//
//  MenuBarItemManager.swift
//  Ice
//

import Combine
import ScreenCaptureKit

class MenuBarItemManager: ObservableObject {
    private static let queue = DispatchQueue(label: "MenuBarItem Observation Queue", qos: .utility)

    @Published private(set) var menuBarItems = [MenuBarItem]()
    @Published private(set) var visibleItems = [MenuBarItem]()
    @Published private(set) var hiddenItems = [MenuBarItem]()
    @Published private(set) var alwaysHiddenItems = [MenuBarItem]()

    private weak var appState: AppState?

    private var timer: QueuedTimer?
    private var cancellables = Set<AnyCancellable>()

    init(appState: AppState) {
        self.appState = appState
    }

    func startObservingMenuBarItems() {
        let timer = QueuedTimer(interval: 1, queue: Self.queue) { [weak self] _ in
            guard
                let self,
                let menuBar = appState?.menuBar
            else {
                return
            }
            let content = SharedContent.current
            DispatchQueue.main.async {
                self.updateMenuBarItems(menuBar: menuBar, content: content)
            }
        }
        timer.start(fireImmediately: true)
        self.timer = timer
    }

    func stopObservingMenuBarItems() {
        timer?.stop()
        timer = nil
    }

    private func getMenuBarItemWindows(content: SharedContent) -> [SCWindow] {
        guard let menuBarWindow = content.firstWindow(where: .isMenuBarWindow) else {
            return []
        }
        return content.windows
            .filter { window in
                window.windowLayer == kCGStatusWindowLevel &&
                window.frame.minY == menuBarWindow.frame.minY &&
                window.frame.maxY == menuBarWindow.frame.maxY &&
                window.frame.width < menuBarWindow.frame.width &&
                window.owningApplication?.processID != ProcessInfo.processInfo.processIdentifier
            }
            .sorted { first, second in
                first.frame.minX < second.frame.minX
            }
    }

    private func updateMenuBarItems(menuBar: MenuBar, content: SharedContent) {
        let windows = getMenuBarItemWindows(content: content)
        let menuBarItems = windows.map { window in
            MenuBarItem(window: window)
        }
        guard
            menuBarItems != self.menuBarItems,
            let visibleSection = menuBar.section(withName: .visible),
            let hiddenSection = menuBar.section(withName: .hidden),
            let alwaysHiddenSection = menuBar.section(withName: .alwaysHidden)
        else {
            return
        }
        self.menuBarItems = menuBarItems
        visibleItems = menuBarItems
            .filter { item in
                item.frame.midX > (hiddenSection.controlItem.windowFrame?.midX ?? 0) &&
                item.windowID != visibleSection.controlItem.windowID
            }
        if alwaysHiddenSection.isEnabled {
            hiddenItems = menuBarItems
                .filter { item in
                    item.frame.midX < (hiddenSection.controlItem.windowFrame?.midX ?? 0) &&
                    item.frame.midX > (alwaysHiddenSection.controlItem.windowFrame?.midX ?? 0) &&
                    item.windowID != hiddenSection.controlItem.windowID &&
                    item.windowID != alwaysHiddenSection.controlItem.windowID
                }
            alwaysHiddenItems = menuBarItems
                .filter { item in
                    item.frame.midX < (alwaysHiddenSection.controlItem.windowFrame?.midX ?? 0) &&
                    item.windowID != alwaysHiddenSection.controlItem.windowID
                }
        } else {
            hiddenItems = menuBarItems
                .filter { item in
                    item.frame.midX < (hiddenSection.controlItem.windowFrame?.midX ?? 0) &&
                    item.windowID != hiddenSection.controlItem.windowID
                }
            alwaysHiddenItems = []
        }
    }
}
