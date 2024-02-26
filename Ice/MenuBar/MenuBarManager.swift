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
    /// should be shown when the mouse pointer hovers over an
    /// empty area of the menu bar.
    @Published var showOnHover = false

    /// A Boolean value that indicates whether the hidden section
    /// should be shown when the mouse pointer clicks in an empty
    /// area of the menu bar.
    @Published var showOnClick = false

    /// A Boolean value that indicates whether the user has
    /// interacted with the menu bar, preventing the "show on
    /// hover" feature from activating.
    @Published var showOnHoverPreventedByUserInteraction = false

    /// A Boolean value that indicates whether the hidden section
    /// should automatically rehide.
    @Published var autoRehide = false

    /// A strategy that determines how the auto-rehide feature works.
    @Published var rehideStrategy: RehideStrategy = .smart

    /// A time interval for the auto-rehide feature when its rule
    /// is ``RehideStrategy/timed``.
    @Published var rehideInterval: TimeInterval = 15

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
    private var mainMenuMaxX: CGFloat = 0

    private var cancellables = Set<AnyCancellable>()

    private let encoder = JSONEncoder()

    private let decoder = JSONDecoder()

    private let defaults = UserDefaults.standard

    private(set) weak var appState: AppState?

    private(set) lazy var appearanceManager = MenuBarAppearanceManager(
        menuBarManager: self,
        encoder: encoder,
        decoder: decoder,
        defaults: defaults
    )

    private lazy var mouseMonitor = UniversalEventMonitor(
        mask: [.mouseMoved, .leftMouseUp, .leftMouseDown, .rightMouseDown]
    ) { [weak self] event in
        guard let self else {
            return event
        }

        switch event.type {
        case .mouseMoved:
            guard
                showOnHover,
                !showOnHoverPreventedByUserInteraction,
                let hiddenSection = section(withName: .hidden)
            else {
                break
            }
            if hiddenSection.isHidden {
                func isMouseInEmptyMenuBarSpace() -> Bool {
                    guard
                        let screen = NSScreen.main,
                        screen.isMouseInMenuBar,
                        let controlItemPosition = hiddenSection.controlItem.position
                    else {
                        return false
                    }
                    return NSEvent.mouseLocation.x > mainMenuMaxX &&
                    screen.frame.maxX - NSEvent.mouseLocation.x > controlItemPosition
                }
                if isMouseInEmptyMenuBarSpace() {
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                        // make sure the mouse is still inside
                        if isMouseInEmptyMenuBarSpace() {
                            hiddenSection.show()
                        }
                    }
                }
            } else {
                func isMouseOutsideMenuBar() -> Bool {
                    guard let screen = NSScreen.main else {
                        return false
                    }
                    return NSEvent.mouseLocation.y < screen.visibleFrame.maxY ||
                    NSEvent.mouseLocation.y > screen.frame.maxY
                }
                if isMouseOutsideMenuBar() {
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                        // make sure the mouse is still outside
                        if isMouseOutsideMenuBar() {
                            hiddenSection.hide()
                        }
                    }
                }
            }
        case .leftMouseUp:
            // make sure auto-rehide is enabled and set to "Smart"
            guard
                autoRehide,
                case .smart = rehideStrategy
            else {
                break
            }

            // make sure the mouse is not in the menu bar
            guard
                let screen = NSScreen.main,
                !screen.isMouseInMenuBar
            else {
                break
            }

            // get the window that the user has clicked into
            guard
                let hiddenSection = section(withName: .hidden),
                let flippedMouseLocation = NSEvent.flippedMouseLocation,
                let windowUnderMouse = WindowInfo.getCurrent(option: .optionOnScreenOnly)
                    .filter({ $0.windowLayer < CGWindowLevelForKey(.cursorWindow) })
                    .first(where: { $0.frame.contains(flippedMouseLocation) }),
                let owningApplication = windowUnderMouse.owningApplication
            else {
                break
            }

            // the dock is an exception to the following check
            if owningApplication.bundleIdentifier != "com.apple.dock" {
                // only continue if the user has clicked into an
                // active window with a regular activation policy
                guard
                    owningApplication.isActive,
                    owningApplication.activationPolicy == .regular
                else {
                    break
                }
            }

            // if all the above checks have passed, hide
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                hiddenSection.hide()
            }
        case .leftMouseDown:
            guard
                let visibleSection = section(withName: .visible),
                let visibleControlItemFrame = visibleSection.controlItem.windowFrame
            else {
                break
            }
            func isMouseInEmptyMenuBarSpace() -> Bool {
                guard
                    let screen = NSScreen.main,
                    screen.isMouseInMenuBar,
                    let hiddenSection = section(withName: .hidden),
                    let controlItemPosition = hiddenSection.controlItem.position
                else {
                    return false
                }
                return NSEvent.mouseLocation.x > mainMenuMaxX &&
                screen.frame.maxX - NSEvent.mouseLocation.x > controlItemPosition
            }
            if isMouseInEmptyMenuBarSpace() {
                showOnHoverPreventedByUserInteraction = true
                if
                    showOnClick,
                    let hiddenSection = section(withName: .hidden)
                {
                    // small delay for better user experience
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                        hiddenSection.show()
                    }
                }
            } else if visibleControlItemFrame.contains(NSEvent.mouseLocation) {
                showOnHoverPreventedByUserInteraction = true
            }
        case .rightMouseDown:
            func handleSection(_ section: MenuBarSection) {
                guard
                    let controlItemPosition = section.controlItem.position,
                    NSEvent.mouseLocation.x > mainMenuMaxX,
                    let screen = NSScreen.main,
                    screen.isMouseInMenuBar,
                    screen.frame.maxX - NSEvent.mouseLocation.x > controlItemPosition
                else {
                    return
                }
                showRightClickMenu(at: NSEvent.mouseLocation)
            }
            if
                let hiddenSection = section(withName: .hidden),
                hiddenSection.isHidden
            {
                handleSection(hiddenSection)
            } else if
                let alwaysHiddenSection = section(withName: .alwaysHidden),
                alwaysHiddenSection.isHidden
            {
                handleSection(alwaysHiddenSection)
            }
        default:
            break
        }

        return event
    }

    /// Initializes a new menu bar manager instance.
    init(appState: AppState) {
        self.appState = appState
    }

    /// Performs the initial setup of the menu bar.
    func performSetup() {
        loadInitialState()
        configureCancellables()
        initializeSections()
        mouseMonitor.start()
        appearanceManager.performSetup()
    }

    /// Loads data from storage and sets the initial state of the
    /// menu bar from that data.
    private func loadInitialState() {
        customIceIconIsTemplate = defaults.bool(forKey: Defaults.customIceIconIsTemplate)
        showOnHover = defaults.bool(forKey: Defaults.showOnHover)
        showOnClick = defaults.bool(forKey: Defaults.showOnClick)
        autoRehide = defaults.bool(forKey: Defaults.autoRehide)

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
        if let rawValue = defaults.object(forKey: Defaults.secondaryActionModifier) as? Int {
            secondaryActionModifier = Hotkey.Modifiers(rawValue: rawValue)
        }
        if
            let rawValue = defaults.object(forKey: Defaults.rehideStrategy) as? Int,
            let strategy = RehideStrategy(rawValue: rawValue)
        {
            rehideStrategy = strategy
        }
        if let interval = defaults.object(forKey: Defaults.rehideInterval) as? TimeInterval {
            rehideInterval = interval
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

        NSWorkspace.shared.publisher(for: \.frontmostApplication)
            .sink { [weak self] frontmostApplication in
                self?.handleFrontmostApplication(frontmostApplication)
            }
            .store(in: &c)

        Publishers.MergeMany(sections.map { $0.controlItem.$position })
            .throttle(for: 0.1, scheduler: DispatchQueue.main, latest: true)
            .sink { [weak self] _ in
                self?.assignControlItemsByPosition()
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

        // propagate changes up from child observable objects
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

    /// Returns the menu bar section with the given name.
    func section(withName name: MenuBarSection.Name) -> MenuBarSection? {
        sections.first { $0.name == name }
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
    private func handleFrontmostApplication(_ frontmostApplication: NSRunningApplication?) {
        guard let frontmostApplication else {
            return
        }

        let appID = frontmostApplication.localizedName ?? "PID \(frontmostApplication.processIdentifier)"
        Logger.menuBarManager.debug("New frontmost application: \(appID)")

        if
            case .focusedApp = rehideStrategy,
            let hiddenSection = section(withName: .hidden)
        {
            // small delay for better user experience
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                hiddenSection.hide()
            }
        }

        // FIXME: Find a better way to cancel the observation from within the call
        // to `sink`, other than storing the cancellable in an Optional box object

        // wait until the application is finished launching
        var box: BoxObject<AnyCancellable?>? = BoxObject()
        box?.base = frontmostApplication.publisher(for: \.isFinishedLaunching)
            .combineLatest(frontmostApplication.publisher(for: \.ownsMenuBar))
            .sink { [weak self] isFinishedLaunching, ownsMenuBar in
                // Ice never actually owns the menu bar, so exclude it from the check
                if frontmostApplication.processIdentifier != ProcessInfo.processInfo.processIdentifier {
                    guard ownsMenuBar else {
                        Logger.menuBarManager.debug("\(appID) does not own menu bar")
                        return
                    }
                }
                guard isFinishedLaunching else {
                    Logger.menuBarManager.debug("\(appID) is launching...")
                    return
                }

                Logger.menuBarManager.debug("\(appID) is finished launching")

                defer {
                    box = nil
                }

                guard let self else {
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
    }

    /// Updates the control item for each section based on the
    /// current control item positions.
    private func assignControlItemsByPosition() {
        let sortedControlItems = sections.lazy
            .map { section in
                section.controlItem
            }
            .sorted { first, second in
                // invisible items should preserve their ordering
                if !first.isVisible {
                    return false
                }
                if !second.isVisible {
                    return true
                }
                // expanded items should preserve their ordering
                switch (first.state, second.state) {
                case (.showItems, .showItems):
                    return (first.position ?? 0) < (second.position ?? 0)
                case (.hideItems, _):
                    return !first.expandsOnHide
                case (_, .hideItems):
                    return second.expandsOnHide
                }
            }
        // assign the items to their new sections
        for index in 0..<sections.count {
            sections[index].controlItem = sortedControlItems[index]
        }
    }
}

// MARK: MenuBarManager: BindingExposable
extension MenuBarManager: BindingExposable { }

// MARK: - Logger
private extension Logger {
    static let menuBarManager = Logger(category: "MenuBarManager")
}
