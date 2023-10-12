//
//  MenuBarItemManager.swift
//  Ice
//

import Combine
import ScreenCaptureKit

class MenuBarItemManager: ObservableObject {
    @Published var visibleItems = [MenuBarItem]()
    @Published var hiddenItems = [MenuBarItem]()
    @Published var alwaysHiddenItems = [MenuBarItem]()

    private var cancellables = Set<AnyCancellable>()

    private(set) weak var menuBar: MenuBar?

    init(menuBar: MenuBar) {
        self.menuBar = menuBar
        updateMenuBarItems(windows: menuBar.sharedContent.windows)
        configureCancellables()
    }

    private func configureCancellables() {
        var c = Set<AnyCancellable>()

        menuBar?.sharedContent.$windows
            .receive(on: DispatchQueue.main)
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
            let visibleSection = menuBar.section(withName: .visible),
            let hiddenSection = menuBar.section(withName: .hidden)
        else {
            return
        }
        let sortedWindows = windows
            .filter { window in
                windowIsMenuBarItem(window, in: menuBarWindow) &&
                !windowIsOwnedByIce(window) &&
                !windowIsHiddenMenuBarItem(window, in: menuBarWindow)
            }
            .sorted { first, second in
                first.frame.minX < second.frame.minX
            }
        visibleItems = sortedWindows
            .filter { window in
                window.frame.midX > (hiddenSection.controlItem.windowFrame?.midX ?? 0) &&
                window.windowID != visibleSection.controlItem.windowID
            }
            .compactMap { window in
                WindowCaptureManager
                    .captureImage(windows: [window], options: .ignoreFraming)
                    .map { image in
                        MenuBarItem(window: window, image: image)
                    }
            }
        guard let alwaysHiddenSection = menuBar.section(withName: .alwaysHidden) else {
            return
        }
        if alwaysHiddenSection.isEnabled {
            hiddenItems = sortedWindows
                .filter { window in
                    window.frame.midX < (hiddenSection.controlItem.windowFrame?.midX ?? 0) &&
                    window.frame.midX > (alwaysHiddenSection.controlItem.windowFrame?.midX ?? 0) &&
                    window.windowID != hiddenSection.controlItem.windowID &&
                    window.windowID != alwaysHiddenSection.controlItem.windowID
                }
                .compactMap { window in
                    WindowCaptureManager
                        .captureImage(windows: [window], options: .ignoreFraming)
                        .map { image in
                            MenuBarItem(window: window, image: image)
                        }
                }
            alwaysHiddenItems = sortedWindows
                .filter { window in
                    window.frame.midX < (alwaysHiddenSection.controlItem.windowFrame?.midX ?? 0) &&
                    window.windowID != alwaysHiddenSection.controlItem.windowID
                }
                .compactMap { window in
                    WindowCaptureManager
                        .captureImage(windows: [window], options: .ignoreFraming)
                        .map { image in
                            MenuBarItem(window: window, image: image)
                        }
                }
        } else {
            hiddenItems = sortedWindows
                .filter { window in
                    window.frame.midX < (hiddenSection.controlItem.windowFrame?.midX ?? 0) &&
                    window.windowID != hiddenSection.controlItem.windowID
                }
                .compactMap { window in
                    WindowCaptureManager
                        .captureImage(windows: [window], options: .ignoreFraming)
                        .map { image in
                            MenuBarItem(window: window, image: image)
                        }
                }
        }
    }

    /// Returns a Boolean value indicating whether the given window
    /// is a menu bar.
    ///
    /// - Parameter window: The window to check.
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
        window.frame.height == menuBarWindow.frame.height &&
        window.frame.width < menuBarWindow.frame.width
    }

    /// Returns a Boolean value indicating whether the given window
    /// is owned by the app.
    ///
    /// - Parameter window: The window to check.
    private func windowIsOwnedByIce(_ window: SCWindow) -> Bool {
        window.owningApplication?.processID == ProcessInfo.processInfo.processIdentifier
    }

    /// Returns a Boolean value indicating whether the given window
    /// is a hidden menu bar item.
    ///
    /// - Parameters:
    ///   - window: The window to check.
    ///   - menuBarWindow: A window to treat as a menu bar when determining
    ///     if `window` is one of its items. This window must return `true`
    ///     when passed to a call to ``windowIsMenuBar(_:)``.
    private func windowIsHiddenMenuBarItem(_ window: SCWindow, in menuBarWindow: SCWindow) -> Bool {
        guard windowIsMenuBarItem(window, in: menuBarWindow) else {
            return false
        }
        var isOnAnotherDesktop: Bool {
            // offscreen windows with empty titles likely belong to another
            // desktop; if a desktop's wallpaper causes the items to invert
            // their colors, two sets of items are created and the ones not
            // currently in use are kept offscreen
            (window.title ?? "").isEmpty && !window.isOnScreen
        }
        var isAudioVideoModule: Bool {
            window.owningApplication?.bundleIdentifier == "com.apple.controlcenter" &&
            window.title == "AudioVideoModule"
        }
        var isTextInputMenuAgent: Bool {
            window.owningApplication?.bundleIdentifier == "com.apple.TextInputMenuAgent"
        }
        return isOnAnotherDesktop || isAudioVideoModule || isTextInputMenuAgent
    }
}
