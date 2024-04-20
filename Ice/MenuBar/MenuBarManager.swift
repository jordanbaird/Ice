//
//  MenuBarManager.swift
//  Ice
//

import AXSwift
import Combine
import OSLog
import SwiftUI

/// Manager for the state of the menu bar.
@MainActor
final class MenuBarManager: ObservableObject {
    @Published private(set) var isHidingApplicationMenus = false

    private(set) weak var appState: AppState?

    private(set) var sections = [MenuBarSection]()

    let appearanceManager: MenuBarAppearanceManager

    let itemManager: MenuBarItemManager

    private let encoder = JSONEncoder()

    private let decoder = JSONDecoder()

    private var applicationMenuFrames = [CGDirectDisplayID: CGRect]()

    private var cancellables = Set<AnyCancellable>()

    /// Initializes a new menu bar manager instance.
    init(appState: AppState) {
        self.appearanceManager = MenuBarAppearanceManager(appState: appState)
        self.itemManager = MenuBarItemManager(appState: appState)
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
                    Task {
                        try await Task.sleep(for: .seconds(0.1))
                        hiddenSection.hide()
                    }
                }
            }
            .store(in: &c)

        // update the application menu frames
        Publishers.CombineLatest3(
            NSWorkspace.shared.publisher(for: \.frontmostApplication),
            NSWorkspace.shared.publisher(for: \.frontmostApplication?.isFinishedLaunching),
            NSWorkspace.shared.publisher(for: \.frontmostApplication?.ownsMenuBar)
        )
        .throttle(for: 1, scheduler: DispatchQueue.main, latest: true)
        .sink { [weak self] _ in
            Task {
                await self?.updateApplicationMenuFrames()
            }
        }
        .store(in: &c)

        // hide application menus when a section is shown (if applicable)
        Publishers.MergeMany(sections.map { $0.$isHidden })
            .removeDuplicates()
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
                                let screen = NSScreen.main,
                                let display = DisplayInfo(nsScreen: screen),
                                try await !self.isFullscreen(for: display)
                            else {
                                return
                            }

                            // get the application menu frame for the display
                            guard let applicationMenuFrame = self.applicationMenuFrames[display.displayID] else {
                                return
                            }

                            let items = try await self.itemManager.menuBarItems(for: display, onScreenOnly: true)

                            // get the leftmost item on the screen; the application menu should
                            // be hidden if the item's minX is close to the maxX of the menu
                            guard let leftmostItem = items.min(by: { $0.frame.minX < $1.frame.minX }) else {
                                return
                            }

                            // offset the leftmost item's minX by its width to give ourselves
                            // a little wiggle room
                            let offsetMinX = leftmostItem.frame.minX - leftmostItem.frame.width

                            // if the offset value is less than or equal to the maxX of the
                            // application menu frame, activate the app to hide the menu
                            if offsetMinX <= applicationMenuFrame.maxX {
                                self.hideApplicationMenus()
                            }
                        } else if
                            self.isHidingApplicationMenus,
                            appState.settingsWindow?.isVisible == false
                        {
                            try await Task.sleep(for: .seconds(0.1))
                            self.showApplicationMenus()
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

    private func updateApplicationMenuFrames() async {
        var applicationMenuFrames = [CGDirectDisplayID: CGRect]()
        for screen in NSScreen.screens {
            guard let display = DisplayInfo(nsScreen: screen) else {
                Logger.menuBarManager.notice("No display for displayID \(screen.displayID)")
                continue
            }
            do {
                let menuBar = try await AccessibilityMenuBar(display: display)
                let items = try menuBar.menuBarItems()
                let frame: CGRect = try items.reduce(into: .zero) { frame, item in
                    frame = try frame.union(item.frame())
                }
                applicationMenuFrames[display.displayID] = frame
            } catch {
                Logger.menuBarManager.error("Couldn't update application menu frame for display \(display.displayID), error: \(error)")
                continue
            }
        }
        self.applicationMenuFrames = applicationMenuFrames
    }

    /// Shows the right-click menu.
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

    func hideApplicationMenus() {
        isHidingApplicationMenus = true
        appState?.activate(withPolicy: .regular)
    }

    func showApplicationMenus() {
        appState?.deactivate(withPolicy: .accessory)
        isHidingApplicationMenus = false
    }

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

    /// Returns the frame of the application menu for the given display.
    func applicationMenuFrame(for display: DisplayInfo) -> CGRect? {
        applicationMenuFrames[display.displayID]
    }
}

extension MenuBarManager {
    /// Returns a Boolean value that indicates whether a window is
    /// fullscreen on the given display.
    func isFullscreen(for display: DisplayInfo) throws -> Bool {
        let windows = try WindowInfo.getOnScreenWindows(excludeDesktopWindows: false)
        return windows.contains(where: Predicates.fullscreenBackdropWindow(for: display))
    }

    /// Asynchronously returns a Boolean value that indicates whether
    /// a window is fullscreen on the given display.
    func isFullscreen(for display: DisplayInfo) async throws -> Bool {
        let windows = try await WindowInfo.onScreenWindows(excludeDesktopWindows: false)
        return windows.contains(where: Predicates.fullscreenBackdropWindow(for: display))
    }
}

// MARK: MenuBarManager: BindingExposable
extension MenuBarManager: BindingExposable { }

// MARK: - Logger
private extension Logger {
    static let menuBarManager = Logger(category: "MenuBarManager")
}
