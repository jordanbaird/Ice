//
//  MenuBarManager.swift
//  Ice
//

import AXSwift
import Combine
import SwiftUI

/// Manager for the state of the menu bar.
@MainActor
final class MenuBarManager: ObservableObject {
    /// Information for the menu bar's average color.
    @Published private(set) var averageColorInfo: MenuBarAverageColorInfo?

    /// A Boolean value that indicates whether the menu bar should be treated
    /// as hidden by the system in the active space. This is derived from the
    /// user's menu bar auto-hide settings, transient system presentation
    /// options, and the active space type.
    @Published private(set) var isMenuBarHiddenBySystem = false

    /// A Boolean value that indicates whether the menu bar is hidden by the system
    /// on desktop spaces according to a value stored in UserDefaults.
    @Published private(set) var isMenuBarHiddenBySystemUserDefaults = false

    /// A Boolean value that indicates whether system presentation options are
    /// currently hiding the menu bar, such as during Mission Control/Expose.
    @Published private(set) var isMenuBarHiddenBySystemPresentationOptions = false

    /// The shared app state.
    private weak var appState: AppState?

    /// Storage for internal observers.
    private var cancellables = Set<AnyCancellable>()

    /// A Boolean value that indicates whether the application menus are hidden.
    private var isHidingApplicationMenus = false

    /// The managed sections in the menu bar.
    private(set) var sections = [MenuBarSection]()

    /// The panel that contains the Ice Bar interface.
    let iceBarPanel: IceBarPanel

    /// The panel that contains the menu bar search interface.
    let searchPanel: MenuBarSearchPanel

    /// Global defaults keys used by System Settings' "Automatically hide and
    /// show the menu bar" setting.
    private enum SystemMenuBarDefaultsKey {
        static let autoHideOnDesktop = "_HIHideMenuBar"
        static let visibleInFullscreen = "AppleMenuBarVisibleInFullscreen"
    }

    /// A Boolean value that indicates whether the manager can update its stored
    /// information for the menu bar's average color.
    private var canUpdateAverageColorInfo: Bool {
        appState?.settingsWindow?.isVisible == true
    }

    /// Initializes a new menu bar manager instance.
    init(appState: AppState) {
        self.iceBarPanel = IceBarPanel(appState: appState)
        self.searchPanel = MenuBarSearchPanel(appState: appState)
        self.appState = appState
    }

    /// Performs the initial setup of the menu bar manager.
    func performSetup() {
        initializeSections()
        configureCancellables()
        iceBarPanel.performSetup()
    }

    /// Performs the initial setup of the menu bar manager's sections.
    private func initializeSections() {
        // Make sure initialization can only happen once.
        guard sections.isEmpty else {
            Logger.menuBarManager.warning("Sections already initialized")
            return
        }

        guard let appState else {
            Logger.menuBarManager.error("Error initializing menu bar sections: Missing app state")
            return
        }

        sections = [
            MenuBarSection(name: .visible, appState: appState),
            MenuBarSection(name: .hidden, appState: appState),
            MenuBarSection(name: .alwaysHidden, appState: appState),
        ]
    }

    /// Configures the internal observers for the manager.
    private func configureCancellables() {
        var c = Set<AnyCancellable>()

        refreshSystemMenuBarHiddenState()
        refreshSystemPresentationOptions(NSApp.currentSystemPresentationOptions)

        NSApp.publisher(for: \.currentSystemPresentationOptions)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] options in
                self?.refreshSystemPresentationOptions(options)
            }
            .store(in: &c)

        appState?.$isActiveSpaceFullscreen
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.refreshSystemMenuBarHiddenState()
            }
            .store(in: &c)

        NotificationCenter.default.publisher(for: UserDefaults.didChangeNotification)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.refreshSystemMenuBarHiddenState()
            }
            .store(in: &c)

        if
            let hiddenSection = section(withName: .alwaysHidden),
            let window = hiddenSection.controlItem.window
        {
            window.publisher(for: \.frame)
                .map { $0.origin.y }
                .removeDuplicates()
                .receive(on: DispatchQueue.main)
                .sink { [weak self] _ in
                    self?.refreshSystemMenuBarHiddenState()
                }
                .store(in: &c)
        }

        // Handle the `focusedApp` rehide strategy.
        NSWorkspace.shared.publisher(for: \.frontmostApplication)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                if
                    let self,
                    let appState,
                    case .focusedApp = appState.settingsManager.generalSettingsManager.rehideStrategy,
                    let hiddenSection = section(withName: .hidden),
                    !appState.eventManager.isMouseInsideMenuBar
                {
                    Task {
                        try await Task.sleep(for: .seconds(0.1))
                        hiddenSection.hide()
                    }
                }
            }
            .store(in: &c)

        appState?.settingsWindow?.publisher(for: \.isVisible)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.updateAverageColorInfo()
            }
            .store(in: &c)

        Timer.publish(every: 5, on: .main, in: .default)
            .autoconnect()
            .sink { [weak self] _ in
                self?.updateAverageColorInfo()
            }
            .store(in: &c)

        // Hide application menus when a section is shown (if applicable).
        Publishers.MergeMany(sections.map { $0.controlItem.$state })
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                guard
                    let self,
                    let appState
                else {
                    return
                }

                // Don't continue if:
                //   * The "HideApplicationMenus" setting isn't enabled.
                //   * The menu bar is hidden by the system.
                //   * The active space is fullscreen.
                //   * The settings window is visible.
                guard
                    appState.settingsManager.advancedSettingsManager.hideApplicationMenus,
                    !isMenuBarHiddenBySystem,
                    !appState.isActiveSpaceFullscreen,
                    appState.settingsWindow?.isVisible == false
                else {
                    return
                }

                if sections.contains(where: { $0.controlItem.state == .showItems }) {
                    guard let screen = NSScreen.main else {
                        return
                    }

                    let displayID = screen.displayID

                    // Get the application menu frame for the display.
                    guard let applicationMenuFrame = getApplicationMenuFrame(for: displayID) else {
                        return
                    }

                    // Get all items.
                    var items = MenuBarItem.getMenuBarItems(on: displayID, onScreenOnly: false, activeSpaceOnly: true)

                    // Filter the items down according to the currently enabled/shown sections.
                    if
                        let alwaysHiddenSection = section(withName: .alwaysHidden),
                        alwaysHiddenSection.isEnabled
                    {
                        if alwaysHiddenSection.controlItem.state == .hideItems {
                            if let alwaysHiddenControlItem = items.firstIndex(matching: .alwaysHiddenControlItem).map({ items.remove(at: $0) }) {
                                items.trimPrefix { $0.frame.maxX <= alwaysHiddenControlItem.frame.minX }
                            }
                        }
                    } else {
                        if let hiddenControlItem = items.firstIndex(matching: .hiddenControlItem).map({ items.remove(at: $0) }) {
                            items.trimPrefix { $0.frame.maxX <= hiddenControlItem.frame.minX }
                        }
                    }

                    // Get the leftmost item on the screen.
                    guard let leftmostItem = items.min(by: { $0.frame.minX < $1.frame.minX }) else {
                        return
                    }

                    // If the minX of the item is less than or equal to the maxX of the
                    // application menu frame, activate the app to hide the menu.
                    if leftmostItem.frame.minX <= applicationMenuFrame.maxX {
                        hideApplicationMenus()
                    }
                } else if isHidingApplicationMenus {
                    showApplicationMenus()
                }
            }
            .store(in: &c)

        cancellables = c
    }

    /// Refreshes the system menu bar hidden state for the active space.
    private func refreshSystemMenuBarHiddenState() {
        let isMenuBarHiddenOnDesktop = self.isMenuBarHiddenOnDesktop
        let isActiveSpaceFullscreen = appState?.isActiveSpaceFullscreen
            ?? Bridging.isSpaceFullscreen(Bridging.activeSpaceID)
        let isMenuBarHiddenInActiveSpace = isActiveSpaceFullscreen
            ? isMenuBarHiddenInFullscreen
            : isMenuBarHiddenOnDesktop
        let isMenuBarHidden = isMenuBarHiddenInActiveSpace
            || isMenuBarHiddenBySystemPresentationOptions

        if isMenuBarHiddenBySystemUserDefaults != isMenuBarHiddenOnDesktop {
            isMenuBarHiddenBySystemUserDefaults = isMenuBarHiddenOnDesktop
        }
        if isMenuBarHiddenBySystem != isMenuBarHidden {
            isMenuBarHiddenBySystem = isMenuBarHidden
        }
    }

    /// Refreshes the transient presentation-options hidden state.
    private func refreshSystemPresentationOptions(_ options: NSApplication.PresentationOptions) {
        let isMenuBarHidden = options.contains(.hideMenuBar) || options.contains(.autoHideMenuBar)
        if isMenuBarHiddenBySystemPresentationOptions != isMenuBarHidden {
            isMenuBarHiddenBySystemPresentationOptions = isMenuBarHidden
        }
        refreshSystemMenuBarHiddenState()
    }

    /// Returns whether the menu bar should be treated as hidden by the system
    /// on the given screen's current space.
    func isMenuBarHiddenBySystem(on screen: NSScreen) -> Bool {
        if isMenuBarHiddenBySystemPresentationOptions {
            return true
        }
        let isFullscreen = isSpaceFullscreen(on: screen)
        return isFullscreen ? isMenuBarHiddenInFullscreen : isMenuBarHiddenOnDesktop
    }

    /// Returns whether the given screen is currently showing a fullscreen space.
    func isSpaceFullscreen(on screen: NSScreen) -> Bool {
        Bridging.isCurrentSpaceFullscreen(forDisplayWithIdentifier: screen.stableIdentifier)
            ?? appState?.isActiveSpaceFullscreen
            ?? Bridging.isSpaceFullscreen(Bridging.activeSpaceID)
    }

    /// The desktop-space portion of System Settings' menu bar auto-hide mode.
    private var isMenuBarHiddenOnDesktop: Bool {
        globalBool(
            forKey: SystemMenuBarDefaultsKey.autoHideOnDesktop,
            defaultValue: false
        )
    }

    /// The fullscreen-space portion of System Settings' menu bar auto-hide mode.
    private var isMenuBarHiddenInFullscreen: Bool {
        !globalBool(
            forKey: SystemMenuBarDefaultsKey.visibleInFullscreen,
            defaultValue: false
        )
    }

    /// Reads a Boolean from the global domain, accepting the common plist
    /// representations used by `defaults`.
    private func globalBool(forKey key: String, defaultValue: Bool) -> Bool {
        switch Defaults.globalDomain[key] {
        case let value as Bool:
            return value
        case let value as NSNumber:
            return value.boolValue
        case let value as String:
            switch value.lowercased() {
            case "1", "true", "yes":
                return true
            case "0", "false", "no":
                return false
            default:
                return defaultValue
            }
        default:
            return defaultValue
        }
    }

    /// Updates the ``averageColorInfo`` property with the current average color
    /// of the menu bar.
    func updateAverageColorInfo() {
        guard
            canUpdateAverageColorInfo,
            let screen = appState?.settingsWindow?.screen
        else {
            return
        }

        let image: CGImage?
        let source: MenuBarAverageColorInfo.Source

        let windows = WindowInfo.getOnScreenWindows(excludeDesktopWindows: false)
        let displayID = screen.displayID

        if let window = WindowInfo.getMenuBarWindow(from: windows, for: displayID) {
            var bounds = window.frame
            bounds.size.height = 1
            bounds.origin.x = bounds.maxX - (bounds.width / 4)
            bounds.size.width /= 4

            image = ScreenCapture.captureWindow(window.windowID, screenBounds: bounds, option: .nominalResolution)
            source = .menuBarWindow
        } else if let window = WindowInfo.getWallpaperWindow(from: windows, for: displayID) {
            var bounds = window.frame
            bounds.size.height = 1
            bounds.origin.x = bounds.midX
            bounds.size.width /= 2

            image = ScreenCapture.captureWindow(window.windowID, screenBounds: bounds, option: .nominalResolution)
            source = .desktopWallpaper
        } else {
            return
        }

        guard
            let image,
            let color = image.averageColor(makeOpaque: true)
        else {
            return
        }

        let info = MenuBarAverageColorInfo(color: color, source: source)

        if averageColorInfo != info {
            averageColorInfo = info
        }
    }

    /// Returns a Boolean value that indicates whether the given display
    /// has a valid menu bar.
    func hasValidMenuBar(in windows: [WindowInfo], for display: CGDirectDisplayID) -> Bool {
        guard let menuBarWindow = WindowInfo.getMenuBarWindow(from: windows, for: display) else {
            return false
        }
        let position = menuBarWindow.frame.origin
        do {
            let uiElement = try systemWideElement.elementAtPosition(Float(position.x), Float(position.y))
            return try uiElement?.role() == .menuBar
        } catch {
            return false
        }
    }

    /// Returns whether the given screen's menu bar is currently visible.
    ///
    /// `isMenuBarHiddenBySystem` describes policy and transient presentation
    /// state, which can remain true while an auto-hidden menu bar is
    /// temporarily revealed. This helper checks the live WindowServer/AX state,
    /// with Ice's own status-item windows as a short-lived fallback while the
    /// menu bar is animating.
    func isMenuBarCurrentlyVisible(on screen: NSScreen, in windows: [WindowInfo]) -> Bool {
        let displayID = screen.displayID
        if
            WindowInfo.getMenuBarWindow(from: windows, for: displayID)?.alpha ?? 0 > 0,
            hasValidMenuBar(in: windows, for: displayID)
        {
            return true
        }
        return hasVisibleControlItemWindow(on: displayID, in: windows)
    }

    /// Returns whether one of Ice's control item windows is currently visible
    /// on the given display.
    private func hasVisibleControlItemWindow(on display: CGDirectDisplayID, in windows: [WindowInfo]) -> Bool {
        let displayBounds = CGDisplayBounds(display)
        let controlItemWindowIDs = Set(sections.compactMap(\.controlItem.windowID))
        guard !controlItemWindowIDs.isEmpty else {
            return false
        }
        return windows.contains { window in
            controlItemWindowIDs.contains(window.windowID) &&
            window.isOnScreen &&
            window.alpha > 0 &&
            displayBounds.intersects(window.frame)
        }
    }

    /// Returns the frame of the application menu for the given display.
    func getApplicationMenuFrame(for displayID: CGDirectDisplayID) -> CGRect? {
        let displayBounds = CGDisplayBounds(displayID)

        guard
            let menuBar = try? systemWideElement.elementAtPosition(Float(displayBounds.origin.x), Float(displayBounds.origin.y)),
            let role = try? menuBar.role(),
            role == .menuBar,
            let items: [UIElement] = try? menuBar.arrayAttribute(.children)?.filter({ (try? $0.attribute(.enabled)) == true })
        else {
            return nil
        }

        let itemFrames = items.lazy.compactMap { try? $0.attribute(.frame) as CGRect? }
        let applicationMenuFrame = itemFrames.reduce(.null, CGRectUnion)

        if applicationMenuFrame.width <= 0 {
            return nil
        }

        // The Accessibility API returns the menu bar for the active screen, regardless of the
        // display origin used. This workaround prevents an incorrect frame from being returned
        // for inactive displays in multi-display setups where one display has a notch.
        if
            let mainScreen = NSScreen.main,
            let thisScreen = NSScreen.screens.first(where: { $0.displayID == displayID }),
            thisScreen != mainScreen,
            let notchedScreen = NSScreen.screens.first(where: { $0.hasNotch }),
            let leftArea = notchedScreen.auxiliaryTopLeftArea,
            applicationMenuFrame.width >= leftArea.maxX
        {
            return nil
        }

        return applicationMenuFrame
    }

    /// Shows the right-click menu.
    func showRightClickMenu(at point: CGPoint) {
        let menu = NSMenu(title: "Ice")

        let editItem = NSMenuItem(
            title: "Edit Menu Bar Appearance…",
            action: #selector(showAppearanceEditorPopover),
            keyEquivalent: ""
        )
        editItem.target = self
        menu.addItem(editItem)

        menu.addItem(.separator())

        let settingsItem = NSMenuItem(
            title: "Ice Settings…",
            action: #selector(AppDelegate.openSettingsWindow),
            keyEquivalent: ","
        )
        menu.addItem(settingsItem)

        menu.popUp(positioning: nil, at: point, in: nil)
    }

    /// Hides the application menus.
    func hideApplicationMenus() {
        guard let appState else {
            Logger.menuBarManager.error("Error hiding application menus: Missing app state")
            return
        }
        Logger.menuBarManager.info("Hiding application menus")
        appState.activate(withPolicy: .regular)
        isHidingApplicationMenus = true
    }

    /// Shows the application menus.
    func showApplicationMenus() {
        guard let appState else {
            Logger.menuBarManager.error("Error showing application menus: Missing app state")
            return
        }
        Logger.menuBarManager.info("Showing application menus")
        appState.deactivate(withPolicy: .accessory)
        isHidingApplicationMenus = false
    }

    /// Toggles the visibility of the application menus.
    func toggleApplicationMenus() {
        if isHidingApplicationMenus {
            showApplicationMenus()
        } else {
            hideApplicationMenus()
        }
    }

    /// Shows the appearance editor popover, centered under the menu bar.
    @objc private func showAppearanceEditorPopover() {
        guard let appState else {
            Logger.menuBarManager.error("Error showing appearance editor popover: Missing app state")
            return
        }
        let panel = MenuBarAppearanceEditorPanel(appState: appState)
        panel.orderFrontRegardless()
        panel.showAppearanceEditorPopover()
    }

    /// Returns the menu bar section with the given name.
    func section(withName name: MenuBarSection.Name) -> MenuBarSection? {
        sections.first { $0.name == name }
    }
}

// MARK: MenuBarManager: BindingExposable
extension MenuBarManager: BindingExposable { }

// MARK: - MenuBarAverageColorInfo

/// Information for the menu bar's average color.
struct MenuBarAverageColorInfo: Hashable {
    enum Source: Hashable {
        case menuBarWindow
        case desktopWallpaper
    }

    var color: CGColor
    var source: Source
}

// MARK: - Logger
private extension Logger {
    /// Logger to use for the menu bar manager.
    static let menuBarManager = Logger(category: "MenuBarManager")
}
