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
        .throttle(for: 0.5, scheduler: DispatchQueue.main, latest: true)
        .sink { [weak self] _ in
            self?.updateApplicationMenuFrames()
        }
        .store(in: &c)

        // hide application menus when a section is shown (if applicable)
        Publishers.MergeMany(sections.map { $0.$isHidden })
            .removeDuplicates()
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                guard
                    let self,
                    let appState,
                    appState.settingsManager.advancedSettingsManager.hideApplicationMenus
                else {
                    return
                }
                if sections.contains(where: { !$0.isHidden }) {
                    guard let screen = NSScreen.main else {
                        return
                    }

                    let displayID = screen.displayID

                    guard !isFullscreen(for: displayID) else {
                        return
                    }

                    // get the application menu frame for the display
                    guard let applicationMenuFrame = applicationMenuFrames[displayID] else {
                        return
                    }

                    // get the leftmost item on the screen; the application menu should
                    // be hidden if the item's minX is close to the maxX of the menu
                    guard
                        let items = try? itemManager.getMenuBarItems(for: displayID, onScreenOnly: true),
                        let leftmostItem = items.min(by: { $0.frame.minX < $1.frame.minX })
                    else {
                        return
                    }

                    // offset the leftmost item's minX by its width to give ourselves
                    // a little wiggle room
                    let offsetMinX = leftmostItem.frame.minX - leftmostItem.frame.width

                    // if the offset value is less than or equal to the maxX of the
                    // application menu frame, activate the app to hide the menu
                    if offsetMinX <= applicationMenuFrame.maxX {
                        hideApplicationMenus()
                    }
                } else if
                    isHidingApplicationMenus,
                    appState.settingsWindow?.isVisible == false
                {
                    Task {
                        try await Task.sleep(for: .milliseconds(25))
                        self.showApplicationMenus()
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

    private func updateApplicationMenuFrames() {
        var frames = [CGDirectDisplayID: CGRect]()
        for screen in NSScreen.screens {
            let displayID = screen.displayID
            do {
                let menuBar = try AccessibilityMenuBar(display: displayID)
                let items = try menuBar.menuBarItems()
                let frame = try items.reduce(CGRect.zero) { frame, item in
                    try frame.union(item.frame())
                }
                frames[displayID] = frame
            } catch {
                Logger.menuBarManager.error(
                    "Couldn't update application menu frame for display \(displayID) error: \(error)"
                )
            }
        }
        applicationMenuFrames = frames
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

    func hideApplicationMenus() {
        guard let appState else {
            Logger.menuBarManager.error("Error hiding application menus: Missing app state")
            return
        }
        appState.activate(withPolicy: .regular)
        isHidingApplicationMenus = true
    }

    func showApplicationMenus() {
        guard let appState else {
            Logger.menuBarManager.error("Error showing application menus: Missing app state")
            return
        }
        appState.deactivate(withPolicy: .accessory)
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

    /// Returns the frame of the application menu for the given display.
    func applicationMenuFrame(for display: CGDirectDisplayID) -> CGRect? {
        applicationMenuFrames[display]
    }

    /// Returns a Boolean value that indicates whether a window is
    /// fullscreen on the given display.
    func isFullscreen(for display: CGDirectDisplayID) -> Bool {
        guard let windows = try? WindowInfo.getOnScreenWindows(excludeDesktopWindows: false) else {
            return false
        }
        return windows.contains(where: Predicates.fullscreenBackdropWindow(for: display))
    }
}

// MARK: MenuBarManager: BindingExposable
extension MenuBarManager: BindingExposable { }

// MARK: - Logger
private extension Logger {
    static let menuBarManager = Logger(category: "MenuBarManager")
}
