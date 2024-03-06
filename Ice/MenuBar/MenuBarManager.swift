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

    /// An icon to show in the menu bar, with a different image
    /// for when items are visible or hidden.
    @Published var iceIcon: ControlItemImageSet = .defaultIceIcon

    /// A Boolean value that indicates whether custom Ice icons
    /// should be rendered as template images.
    @Published var customIceIconIsTemplate = false

    /// The last user-selected custom Ice icon.
    @Published var lastCustomIceIcon: ControlItemImageSet?

    /// The modifier that triggers the secondary action on the
    /// menu bar's control items.
    @Published var secondaryActionModifier: Hotkey.Modifiers = .option

    /// A Boolean value that indicates whether the hidden section
    /// should be shown when the mouse pointer clicks in an empty
    /// area of the menu bar.
    @Published var showOnClick = true

    /// A Boolean value that indicates whether the hidden section
    /// should be shown when the mouse pointer hovers over an
    /// empty area of the menu bar.
    @Published var showOnHover = false

    /// A Boolean value that indicates whether the user has
    /// interacted with the menu bar, preventing the "show on
    /// hover" feature from activating.
    @Published var showOnHoverPreventedByUserInteraction = false

    /// A Boolean value that indicates whether the hidden section
    /// should automatically rehide.
    @Published var autoRehide = true

    /// A strategy that determines how the auto-rehide feature works.
    @Published var rehideStrategy: RehideStrategy = .smart

    /// A time interval for the auto-rehide feature when its rule
    /// is ``RehideStrategy/timed``.
    @Published var rehideInterval: TimeInterval = 15

    /// A Boolean value that indicates whether the application menus
    /// should be hidden if needed to show all menu bar items.
    @Published var hideApplicationMenus: Bool = false

    /// A Boolean value that indicates whether section divider
    /// control items should be shown.
    @Published var showSectionDividers = false

    /// A Boolean value that indicates whether the Ice icon should
    /// be shown.
    @Published var showIceIcon = true

    /// The sections currently in the menu bar.
    @Published private(set) var sections = [MenuBarSection]() {
        willSet {
            for section in sections {
                section.menuBarManager = nil
            }
        }
        didSet {
            if validateSectionCountOrReinitialize() {
                for section in sections {
                    section.menuBarManager = self
                }
            }
            configureCancellables()
            needsSave = true
        }
    }

    /// The maximum X coordinate of the menu bar's main menu.
    private(set) var mainMenuMaxX: CGFloat = 0

    private var cancellables = Set<AnyCancellable>()

    private let encoder = JSONEncoder()

    private let decoder = JSONDecoder()

    private let defaults = UserDefaults.standard

    private(set) weak var appState: AppState?

    private(set) lazy var itemManager = MenuBarItemManager(menuBarManager: self)

    private(set) lazy var appearanceManager = MenuBarAppearanceManager(menuBarManager: self)

    private(set) lazy var eventMonitorManager = EventMonitorManager(menuBarManager: self)

    /// Initializes a new menu bar manager instance.
    init(appState: AppState) {
        self.appState = appState
    }

    /// Performs the initial setup of the menu bar.
    func performSetup() {
        loadInitialState()
        configureCancellables()
        initializeSections()
        appearanceManager.performSetup()
        eventMonitorManager.performSetup()
    }

    /// Loads data from storage and sets the initial state of the
    /// menu bar from that data.
    private func loadInitialState() {
        defaults.ifPresent(key: Defaults.customIceIconIsTemplate, assign: &customIceIconIsTemplate)
        defaults.ifPresent(key: Defaults.showOnClick, assign: &showOnClick)
        defaults.ifPresent(key: Defaults.showOnHover, assign: &showOnHover)
        defaults.ifPresent(key: Defaults.autoRehide, assign: &autoRehide)
        defaults.ifPresent(key: Defaults.rehideInterval, assign: &rehideInterval)
        defaults.ifPresent(key: Defaults.hideApplicationMenus, assign: &hideApplicationMenus)
        defaults.ifPresent(key: Defaults.showSectionDividers, assign: &showSectionDividers)
        defaults.ifPresent(key: Defaults.showIceIcon, assign: &showIceIcon)
        defaults.ifPresent(key: Defaults.secondaryActionModifier) { rawValue in
            secondaryActionModifier = Hotkey.Modifiers(rawValue: rawValue)
        }
        defaults.ifPresent(key: Defaults.rehideStrategy) { rawValue in
            if let strategy = RehideStrategy(rawValue: rawValue) {
                rehideStrategy = strategy
            }
        }

        if let data = defaults.data(forKey: Defaults.iceIcon) {
            do {
                iceIcon = try decoder.decode(ControlItemImageSet.self, from: data)
            } catch {
                Logger.menuBarManager.error("Error decoding Ice icon: \(error)")
            }
            if case .custom = iceIcon.name {
                lastCustomIceIcon = iceIcon
            }
        }
    }

    /// Performs the initial setup of the menu bar's section list.
    private func initializeSections() {
        guard sections.isEmpty else {
            Logger.menuBarManager.info("Sections already initialized")
            return
        }

        // load sections from persistent storage
        if let sectionsData = defaults.data(forKey: Defaults.sections) {
            do {
                sections = try decoder.decode([MenuBarSection].self, from: sectionsData)
            } catch {
                Logger.menuBarManager.error("Decoding error: \(error)")
                sections = []
            }
        } else {
            sections = []
        }
    }

    /// Save all control items in the menu bar to persistent storage.
    private func saveSections() {
        do {
            let serializedSections = try encoder.encode(sections)
            defaults.set(serializedSections, forKey: Defaults.sections)
            needsSave = false
        } catch {
            Logger.menuBarManager.error("Encoding error: \(error)")
        }
    }

    /// Performs validation on the current section count, reinitializing
    /// the sections if needed.
    ///
    /// - Returns: A Boolean value indicating whether the count was valid.
    private func validateSectionCountOrReinitialize() -> Bool {
        if sections.count != 3 {
            sections = [
                MenuBarSection(name: .visible),
                MenuBarSection(name: .hidden),
                MenuBarSection(name: .alwaysHidden),
            ]
            return false
        }
        return true
    }

    private func configureCancellables() {
        var c = Set<AnyCancellable>()

        Publishers.CombineLatest(
            NSWorkspace.shared.publisher(for: \.frontmostApplication), 
            NSWorkspace.shared.publisher(for: \.frontmostApplication?.ownsMenuBar).map { $0 ?? false }
        )
        .sink { [weak self] frontmostApplication, ownsMenuBar in
            self?.handleFrontmostApplication(frontmostApplication, ownsMenuBar: ownsMenuBar)
        }
        .store(in: &c)

        Publishers.MergeMany(sections.map { $0.$isHidden })
            .delay(for: 0.1, scheduler: DispatchQueue.main)
            .sink { [weak self] _ in
                guard
                    let self,
                    let appState,
                    hideApplicationMenus,
                    case .idle = appState.mode
                else {
                    return
                }
                if sections.contains(where: { !$0.isHidden }) {
                    appState.activate(withPolicy: .regular)
                } else {
                    appState.deactivate(withPolicy: .accessory)
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

        $iceIcon
            .receive(on: DispatchQueue.main)
            .sink { [weak self] iceIcon in
                guard let self else {
                    return
                }
                if case .custom = iceIcon.name {
                    lastCustomIceIcon = iceIcon
                }
                do {
                    let data = try encoder.encode(iceIcon)
                    defaults.set(data, forKey: Defaults.iceIcon)
                } catch {
                    Logger.menuBarManager.error("Error encoding Ice icon: \(error)")
                }
            }
            .store(in: &c)

        $customIceIconIsTemplate
            .receive(on: DispatchQueue.main)
            .sink { [weak self] isTemplate in
                self?.defaults.set(isTemplate, forKey: Defaults.customIceIconIsTemplate)
            }
            .store(in: &c)

        $secondaryActionModifier
            .receive(on: DispatchQueue.main)
            .sink { [weak self] modifier in
                self?.defaults.set(modifier.rawValue, forKey: Defaults.secondaryActionModifier)
            }
            .store(in: &c)

        $showOnHover
            .receive(on: DispatchQueue.main)
            .sink { [weak self] showOnHover in
                self?.defaults.set(showOnHover, forKey: Defaults.showOnHover)
            }
            .store(in: &c)

        $showOnClick
            .receive(on: DispatchQueue.main)
            .sink { [weak self] showOnClick in
                self?.defaults.set(showOnClick, forKey: Defaults.showOnClick)
            }
            .store(in: &c)

        $autoRehide
            .receive(on: DispatchQueue.main)
            .sink { [weak self] autoRehide in
                self?.defaults.set(autoRehide, forKey: Defaults.autoRehide)
            }
            .store(in: &c)

        $rehideStrategy
            .receive(on: DispatchQueue.main)
            .sink { [weak self] strategy in
                self?.defaults.set(strategy.rawValue, forKey: Defaults.rehideStrategy)
            }
            .store(in: &c)

        $rehideInterval
            .receive(on: DispatchQueue.main)
            .sink { [weak self] interval in
                self?.defaults.set(interval, forKey: Defaults.rehideInterval)
            }
            .store(in: &c)

        $hideApplicationMenus
            .receive(on: DispatchQueue.main)
            .sink { [weak self] shouldHide in
                self?.defaults.set(shouldHide, forKey: Defaults.hideApplicationMenus)
            }
            .store(in: &c)

        $showSectionDividers
            .receive(on: DispatchQueue.main)
            .sink { [weak self] shouldShow in
                self?.defaults.set(shouldShow, forKey: Defaults.showSectionDividers)
            }
            .store(in: &c)

        $showIceIcon
            .receive(on: DispatchQueue.main)
            .sink { [weak self] showIceIcon in
                self?.defaults.set(showIceIcon, forKey: Defaults.showIceIcon)
            }
            .store(in: &c)

        // propagate changes up from child observable objects
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

    /// Shows the appearance editor popover, centered under
    /// the menu bar.
    @objc private func showAppearanceEditorPopover() {
        let helperPanel = MenuBarAppearanceEditorHelperPanel()
        helperPanel.orderFrontRegardless()
        helperPanel.showAppearanceEditorPopover()
    }

    /// Handles changes to the frontmost application.
    private func handleFrontmostApplication(_ frontmostApplication: NSRunningApplication?, ownsMenuBar: Bool) {
        guard let frontmostApplication else {
            return
        }

        if
            case .focusedApp = rehideStrategy,
            let hiddenSection = section(withName: .hidden)
        {
            // small delay for better user experience
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                hiddenSection.hide()
            }
        }

        guard ownsMenuBar else {
            return
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { [self] in
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
