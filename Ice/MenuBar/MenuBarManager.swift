//
//  MenuBarManager.swift
//  Ice
//

import AXSwift
import Combine
import OSLog
import SwiftUI

/// Manager for the state of the menu bar.
final class MenuBarManager: ObservableObject {
    /// The frame of the menu bar's application menu.
    @Published private(set) var applicationMenuFrame = CGRect.zero

    private(set) var sections = [MenuBarSection]()

    private(set) weak var appState: AppState?

    private(set) lazy var itemManager = MenuBarItemManager(menuBarManager: self)

    let appearanceManager: MenuBarAppearanceManager

    private var isHidingApplicationMenus = false

    private let encoder = JSONEncoder()

    private let decoder = JSONDecoder()

    private var cancellables = Set<AnyCancellable>()

    /// Initializes a new menu bar manager instance.
    init(appState: AppState) {
        self.appearanceManager = MenuBarAppearanceManager(appState: appState)
        self.appState = appState
    }

    /// Performs the initial setup of the menu bar.
    func performSetup() {
        initializeSections()
        configureCancellables()
        appearanceManager.performSetup()
    }

    /// Performs the initial setup of the menu bar's section list.
    private func initializeSections() {
        // make sure initialization can only happen once
        guard sections.isEmpty else {
            Logger.menuBarManager.warning("Sections already initialized")
            return
        }

        sections = [
            MenuBarSection(name: .visible),
            MenuBarSection(name: .hidden),
            MenuBarSection(name: .alwaysHidden),
        ]

        // assign the global app state to each section
        if let appState {
            for section in sections {
                section.assignAppState(appState)
            }
        }
    }

    private func configureCancellables() {
        var c = Set<AnyCancellable>()

        // handle focusedApp rehide strategy
        NSWorkspace.shared.publisher(for: \.frontmostApplication)
            .sink { [weak self] _ in
                if
                    let self,
                    let appState,
                    case .focusedApp = appState.settingsManager.generalSettingsManager.rehideStrategy,
                    let hiddenSection = section(withName: .hidden)
                {
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                        hiddenSection.hide()
                    }
                }
            }
            .store(in: &c)

        // update the main menu maxX
        Publishers.CombineLatest3(
            NSWorkspace.shared.publisher(for: \.frontmostApplication),
            NSWorkspace.shared.publisher(for: \.frontmostApplication?.isFinishedLaunching),
            NSWorkspace.shared.publisher(for: \.frontmostApplication?.ownsMenuBar)
        )
        .sink { [weak self] frontmostApplication, isFinishedLaunching, _ in
            guard
                let self,
                let frontmostApplication,
                isFinishedLaunching == true
            else {
                return
            }
            do {
                let items = try AccessibilityApplication(frontmostApplication).menuBar().menuBarItems()
                applicationMenuFrame = try items.reduce(into: .zero) { result, item in
                    result = try result.union(item.frame())
                }
            } catch {
                applicationMenuFrame = .zero
                Logger.menuBarManager.error("Error updating application menu frame: \(error)")
            }
        }
        .store(in: &c)

        // hide application menus when a section is shown (if applicable)
        Publishers.MergeMany(sections.map { $0.$isHidden })
            .throttle(for: 0.01, scheduler: DispatchQueue.main, latest: true)
            .sink { [weak self] _ in
                guard
                    let self,
                    let appState,
                    appState.settingsManager.advancedSettingsManager.hideApplicationMenus
                else {
                    return
                }
                Task {
                    do {
                        if self.sections.contains(where: { !$0.isHidden }) {
                            guard
                                let display = DisplayInfo.main,
                                !self.isMenuBarHidden(for: display),
                                !self.isFullscreen(for: display)
                            else {
                                return
                            }

                            let items = try await self.itemManager.menuBarItems(for: display, onScreenOnly: true)

                            // get the leftmost item on the screen; the application menu should
                            // be hidden if the item's minX is close to the maxX of the menu
                            guard let leftmostItem = items.min(by: { $0.frame.minX < $1.frame.minX }) else {
                                return
                            }

                            // offset the leftmost item's minX by twice its width to give
                            // ourselves a little wiggle room
                            let offsetMinX = leftmostItem.frame.minX - (leftmostItem.frame.width * 2)

                            // if the offset value is less than or equal to the maxX of the
                            // application menu frame, activate the app to hide the menu
                            if offsetMinX <= self.applicationMenuFrame.maxX {
                                await self.hideApplicationMenus()
                            }
                        } else if
                            self.isHidingApplicationMenus,
                            await appState.settingsWindow?.isVisible == false
                        {
                            try await Task.sleep(for: .seconds(0.1))
                            await self.showApplicationMenus()
                        }
                    } catch {
                        Logger.menuBarManager.error("ERROR: \(error)")
                    }
                }
            }
            .store(in: &c)

        // propagate changes from child observable objects
        itemManager.objectWillChange
            .sink { [weak self] in
                self?.objectWillChange.send()
            }
            .store(in: &c)
        appearanceManager.objectWillChange
            .sink { [weak self] in
                self?.objectWillChange.send()
            }
            .store(in: &c)

        // propagate changes from all sections
        for section in sections {
            section.objectWillChange
                .sink { [weak self] in
                    self?.objectWillChange.send()
                }
                .store(in: &c)
        }

        cancellables = c
    }

    /// Shows the right-click menu.
    @MainActor
    func showRightClickMenu(at point: CGPoint) {
        let menu = NSMenu(title: Constants.appName)

        let editItem = NSMenuItem(
            title: "Edit Menu Bar Appearance…",
            action: #selector(showAppearanceEditorPopover),
            keyEquivalent: ""
        )
        editItem.target = self
        menu.addItem(editItem)

        menu.addItem(.separator())

        let settingsItem = NSMenuItem(
            title: "\(Constants.appName) Settings…",
            action: #selector(AppDelegate.openSettingsWindow),
            keyEquivalent: ","
        )
        menu.addItem(settingsItem)

        menu.popUp(positioning: nil, at: point, in: nil)
    }

    @MainActor
    func hideApplicationMenus() {
        appState?.activate(withPolicy: .regular)
        isHidingApplicationMenus = true
    }

    @MainActor
    func showApplicationMenus() {
        appState?.deactivate(withPolicy: .accessory)
        isHidingApplicationMenus = false
    }

    @MainActor
    func toggleApplicationMenus() {
        if isHidingApplicationMenus {
            showApplicationMenus()
        } else {
            hideApplicationMenus()
        }
    }

    /// Shows the appearance editor popover, centered under the menu bar.
    @objc private func showAppearanceEditorPopover() {
        let panel = MenuBarAppearanceEditorPanel()
        panel.orderFrontRegardless()
        panel.showAppearanceEditorPopover()
    }

    /// Returns the menu bar section with the given name.
    func section(withName name: MenuBarSection.Name) -> MenuBarSection? {
        sections.first { $0.name == name }
    }

    /// Returns a Boolean value that indicates whether the menu bar is
    /// hidden for the given display.
    func isMenuBarHidden(for display: DisplayInfo) -> Bool {
        guard let menuBarWindow = try? WindowInfo.getMenuBarWindow(for: display) else {
            return true
        }
        return !menuBarWindow.isOnScreen
    }

    /// Returns a Boolean value that indicates whether an app is fullscreen
    /// on the given display.
    func isFullscreen(for display: DisplayInfo) -> Bool {
        let windows: [WindowInfo]
        do {
            windows = try WindowInfo.getCurrent(option: .optionOnScreenOnly)
        } catch {
            return false
        }
        return windows.contains { window in
            window.frame == display.frame &&
            window.owningApplication?.bundleIdentifier == "com.apple.dock" &&
            window.title == "Fullscreen Backdrop"
        }
    }
}

// MARK: MenuBarManager: BindingExposable
extension MenuBarManager: BindingExposable { }

// MARK: - Logger
private extension Logger {
    static let menuBarManager = Logger(category: "MenuBarManager")
}
