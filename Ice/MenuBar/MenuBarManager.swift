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
    /// Set to `true` to tell the menu bar to save its sections.
    @Published var needsSave = false

    /// The maximum X coordinate of the menu bar's main menu.
    @Published private(set) var mainMenuMaxX: CGFloat = 0

    private(set) var sections = [MenuBarSection]()

    private(set) weak var appState: AppState?

    private(set) lazy var itemManager = MenuBarItemManager(menuBarManager: self)

    private(set) lazy var appearanceManager = MenuBarAppearanceManager(menuBarManager: self)

    private var isHidingApplicationMenus = false

    private let encoder = JSONEncoder()

    private let decoder = JSONDecoder()

    private var cancellables = Set<AnyCancellable>()

    /// Initializes a new menu bar manager instance.
    init(appState: AppState) {
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

        // load sections from persistent storage
        if let sectionsData = Defaults.data(forKey: .sections) {
            do {
                sections = try decoder.decode([MenuBarSection].self, from: sectionsData)
            } catch {
                Logger.menuBarManager.error("Decoding error: \(error)")
                sections = []
            }
        } else {
            sections = []
        }

        // validate section count or reinitialize
        if sections.count != 3 {
            sections = [
                MenuBarSection(name: .visible),
                MenuBarSection(name: .hidden),
                MenuBarSection(name: .alwaysHidden),
            ]
        }

        // assign the global app state to each section
        if let appState {
            for section in sections {
                section.assignAppState(appState)
            }
        }
    }

    /// Save all control items in the menu bar to persistent storage.
    private func saveSections() {
        do {
            let serializedSections = try encoder.encode(sections)
            Defaults.set(serializedSections, forKey: .sections)
            needsSave = false
        } catch {
            Logger.menuBarManager.error("Encoding error: \(error)")
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
        Publishers.CombineLatest(
            NSWorkspace.shared.publisher(for: \.frontmostApplication), 
            NSWorkspace.shared.publisher(for: \.frontmostApplication?.ownsMenuBar)
        )
        .sink { [weak self] frontmostApplication, _ in
            guard
                let self,
                let frontmostApplication
            else {
                return
            }
            do {
                guard
                    let application = Application(frontmostApplication),
                    let menuBar: UIElement = try application.attribute(.menuBar),
                    let children: [UIElement] = try menuBar.arrayAttribute(.children)
                else {
                    mainMenuMaxX = 0
                    return
                }
                mainMenuMaxX = try children.reduce(into: 0) { result, child in
                    if let frame: CGRect = try child.attribute(.frame) {
                        result += frame.width
                    }
                }
            } catch {
                mainMenuMaxX = 0
                Logger.menuBarManager.error("Error updating main menu maxX: \(error)")
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
                if sections.contains(where: { !$0.isHidden }) {
                    guard let display = DisplayInfo.main else {
                        return
                    }

                    let items = itemManager.getMenuBarItems(for: display, onScreenOnly: true)

                    // get the leftmost item on the screen; the application menu should
                    // be hidden if the item's minX is close to the maxX of the menu
                    guard let leftmostItem = items.min(by: { $0.frame.minX < $1.frame.minX }) else {
                        return
                    }

                    // offset the leftmost item's minX by twice its width to give
                    // ourselves a little wiggle room
                    let offsetMinX = leftmostItem.frame.minX - (leftmostItem.frame.width * 2)

                    // if the offset value is less than or equal to the maxX of the
                    // application menu, activate the app to hide the menu
                    if offsetMinX <= mainMenuMaxX {
                        appState.activate(withPolicy: .regular)
                        isHidingApplicationMenus = true
                    }
                } else if 
                    isHidingApplicationMenus,
                    appState.settingsWindow?.isVisible == false
                {
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                        appState.deactivate(withPolicy: .accessory)
                        self.isHidingApplicationMenus = false
                    }
                }
            }
            .store(in: &c)

        $needsSave
            .debounce(for: 1, scheduler: DispatchQueue.main)
            .sink { [weak self] needsSave in
                if needsSave {
                    self?.saveSections()
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

    /// Shows the appearance editor popover, centered under the menu bar.
    @objc private func showAppearanceEditorPopover() {
        let helperPanel = MenuBarAppearanceEditorHelperPanel()
        helperPanel.orderFrontRegardless()
        helperPanel.showAppearanceEditorPopover()
    }

    /// Returns the menu bar section with the given name.
    func section(withName name: MenuBarSection.Name) -> MenuBarSection? {
        sections.first { $0.name == name }
    }
}

// MARK: MenuBarManager: BindingExposable
extension MenuBarManager: BindingExposable { }

// MARK: - Logger
private extension Logger {
    static let menuBarManager = Logger(category: "MenuBarManager")
}
