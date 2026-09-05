//
//  ControlItem.swift
//  Ice
//

import Cocoa
import Combine

// MARK: - ControlItem

/// A status item that controls a section in the menu bar.
@MainActor
final class ControlItem {
    /// An identifier for a control item.
    enum Identifier: String, CaseIterable {
        /// The identifier for the control item for the visible section.
        case visible = "Ice.ControlItem.Visible"
        /// The identifier for the control item for the hidden section.
        case hidden = "Ice.ControlItem.Hidden"
        /// The identifier for the control item for the always-hidden section.
        case alwaysHidden = "Ice.ControlItem.AlwaysHidden"

        /// A tag for the control item with this identifier.
        var tag: MenuBarItemTag {
            return switch self {
            case .visible: .visibleControlItem
            case .hidden: .hiddenControlItem
            case .alwaysHidden: .alwaysHiddenControlItem
            }
        }

        /// Returns the length associated with this identifier and
        /// the given hiding state.
        func length(for state: HidingState) -> CGFloat {
            if #available(macOS 27.0, *) {
                // A separate blank native spacer handles overflow. This button
                // keeps its normal width and remains clickable in both states.
                return Lengths.standard
            }
            return switch self {
            case .visible:
                Lengths.standard
            case .hidden, .alwaysHidden:
                switch state {
                case .showSection: Lengths.standard
                case .hideSection: Lengths.expanded
                }
            }
        }
    }

    /// A hiding state for a control item.
    enum HidingState: Equatable {
        case showSection
        case hideSection
    }

    /// A namespace for control item lengths.
    private enum Lengths {
        static let standard: CGFloat = NSStatusItem.variableLength
        static let expanded: CGFloat = 10_000
    }

    /// Storage for a control item's underlying status item.
    private final class StatusItemStorage {
        let statusItem: NSStatusItem
        let constraint: NSLayoutConstraint?

        /// Creates a new storage instance.
        @MainActor
        init(controlItem: ControlItem) {
            ControlItemDefaults.preflightSetup(for: controlItem)

            self.statusItem = NSStatusBar.system.statusItem(withLength: 0)
            self.statusItem.autosaveName = controlItem.autosaveName

            if let button = statusItem.button {
                button.setAccessibilityIdentifier(controlItem.identifier.rawValue)
                // This could break in a new macOS release, but we need this constraint in order to
                // be able to hide the status item when the `ShowSectionDividers` setting is disabled.
                // A previous implementation used `statusItem.isVisible`, which was more robust, but
                // would completely remove the status item. With the current set of features, we use
                // the control item positions to determine the items in each section, so we need the
                // status item to be present if its section is enabled. The new solution is to remove
                // a constraint from the item's content view prevents it from having a length of zero.
                // Then, we set the length. FIXME: Find a replacement for this.
                if
                    let constraints = button.window?.contentView?.constraintsAffectingLayout(for: .horizontal),
                    let constraint = constraints.first(where: Predicates.controlItemConstraint(button: button))
                {
                    assert(constraints.filter(Predicates.controlItemConstraint(button: button)).count == 1)
                    self.constraint = constraint
                } else {
                    self.constraint = nil
                }

                button.target = controlItem
                button.action = #selector(controlItem.performAction)
                if #available(macOS 27.0, *) {
                    // Finish the physical click before a requested hide can
                    // realign our own boundary with a native Command-drag.
                    button.sendAction(on: [.leftMouseUp, .rightMouseUp])
                } else {
                    button.sendAction(on: [.leftMouseDown, .rightMouseUp])
                }
            } else {
                self.constraint = nil
            }
        }

        deinit {
            removeStatusItem()
        }

        /// Removes the status item from the status bar.
        private func removeStatusItem() {
            // Removing the status item has the unwanted side effect of
            // deleting the preferred position. Cache and restore it.
            let autosaveName = statusItem.autosaveName as String
            let cached = ControlItemDefaults[.preferredPosition, autosaveName]
            NSStatusBar.system.removeStatusItem(statusItem)
            ControlItemDefaults[.preferredPosition, autosaveName] = cached
        }
    }

    /// The control item's hiding state (`@Published`).
    @Published var state = HidingState.hideSection {
        didSet {
            guard state != oldValue else { return }
            // Keep the button's appearance in the same event turn as its state.
            updateStatusItem()
        }
    }

    /// The control item's window (`@Published`).
    @Published private(set) var window: NSWindow?

    /// The control item's frame (`@Published`).
    @Published private(set) var frame: CGRect?

    /// The control item's screen (`@Published`).
    @Published private(set) var screen: NSScreen?

    /// The control item's frame, if it is onscreen (`@Published`).
    @Published private(set) var onScreenFrame: CGRect?

    /// The control item's identifier.
    let identifier: Identifier

    /// A fresh native identity avoids inheriting experimental host positions.
    var autosaveName: String {
        if #available(macOS 27.0, *), identifier == .visible {
            return identifier.rawValue + ".native.v1"
        }
        return identifier.rawValue
    }

    var preferredPosition: CGFloat {
        ControlItemDefaults[.preferredPosition, autosaveName] ?? 0
    }

    /// Lazy storage for the control item's underlying status item.
    private lazy var storage = StatusItemStorage(controlItem: self)

    /// The shared app state.
    private weak var appState: AppState?

    /// Storage for internal observers.
    private var cancellables = Set<AnyCancellable>()

    /// The control item's underlying status item.
    private var statusItem: NSStatusItem {
        storage.statusItem
    }

    /// A horizontal constraint for the control item's content view.
    private var constraint: NSLayoutConstraint? {
        storage.constraint
    }

    /// A Boolean value that indicates whether the control item serves as
    /// a divider between sections.
    var isSectionDivider: Bool {
        identifier != .visible
    }

    /// A Boolean value that indicates whether the control item is currently
    /// displayed in the menu bar.
    var isAddedToMenuBar: Bool {
        statusItem.isVisible
    }

    /// The corresponding section name for the control item.
    var sectionName: MenuBarSection.Name {
        switch identifier {
        case .visible: .visible
        case .hidden: .hidden
        case .alwaysHidden: .alwaysHidden
        }
    }

    /// Creates a control item with the given identifier.
    init(identifier: Identifier) {
        self.identifier = identifier
    }

    /// Performs the initial setup of the control item.
    func performSetup(with appState: AppState) {
        self.appState = appState
        configureCancellables()
        updateStatusItem()
    }

    /// Configures the internal observers for the control item.
    private func configureCancellables() {
        var c = Set<AnyCancellable>()

        statusItem.publisher(for: \.isVisible)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] isVisible in
                guard
                    let self,
                    let menuBarManager = appState?.menuBarManager,
                    let section = menuBarManager.section(withName: sectionName),
                    let hotkey = section.hotkey
                else {
                    return
                }
                if #available(macOS 27.0, *), self.identifier != .visible {
                    if section.isEnabled {
                        hotkey.enable()
                    } else {
                        hotkey.disable()
                    }
                    return
                }
                if isVisible {
                    hotkey.enable()
                } else {
                    hotkey.disable()
                }
            }
            .store(in: &c)

        statusItem.publisher(for: \.button).removeNil()
            .flatMap { $0.publisher(for: \.window) }
            .receive(on: DispatchQueue.main)
            .sink { [weak self] window in
                self?.window = window
            }
            .store(in: &c)

        $window.removeNil()
            .flatMap { $0.publisher(for: \.frame) }
            .removeDuplicates()
            .receive(on: DispatchQueue.main)
            .sink { [weak self] frame in
                self?.frame = frame
            }
            .store(in: &c)

        $window.removeNil()
            .flatMap { $0.publisher(for: \.screen) }
            .receive(on: DispatchQueue.main)
            .sink { [weak self] screen in
                self?.screen = screen
            }
            .store(in: &c)

        $screen.removeNil()
            .flatMap { $0.publisher(for: \.frame) }
            .combineLatest($frame.removeNil())
            .removeDuplicates()
            .receive(on: DispatchQueue.main)
            .sink { [weak self] screenFrame, frame in
                guard let self else {
                    return
                }
                if screenFrame.intersects(frame) {
                    onScreenFrame = frame
                } else {
                    onScreenFrame = nil
                }
            }
            .store(in: &c)

        if let appState {
            appState.$isDraggingMenuBarItem
                .removeDuplicates()
                .receive(on: DispatchQueue.main)
                .sink { [weak self] isDragging in
                    guard let self else {
                        return
                    }
                    if isDragging {
                        updateStatusItem()
                    }
                }
                .store(in: &c)

            if identifier == .visible {
                appState.settings.general.$showIceIcon
                    .combineLatest(statusItem.publisher(for: \.isVisible))
                    .removeDuplicates()
                    .receive(on: DispatchQueue.main)
                    .sink { [weak self] shouldShow, _ in
                        guard let self else {
                            return
                        }
                        if shouldShow {
                            addToMenuBar()
                        } else {
                            removeFromMenuBar()
                        }
                    }
                    .store(in: &c)

                appState.settings.general.$iceIcon
                    .combineLatest(appState.settings.general.$customIceIconIsTemplate)
                    .removeDuplicates()
                    .receive(on: DispatchQueue.main)
                    .sink { [weak self] _ in
                        self?.updateStatusItem()
                    }
                    .store(in: &c)
            }

            if identifier == .alwaysHidden {
                appState.settings.advanced.$enableAlwaysHiddenSection
                    .combineLatest(statusItem.publisher(for: \.isVisible))
                    .removeDuplicates()
                    .receive(on: DispatchQueue.main)
                    .sink { [weak self] shouldEnable, _ in
                        guard let self else {
                            return
                        }
                        if shouldEnable {
                            addToMenuBar()
                        } else {
                            removeFromMenuBar()
                        }
                    }
                    .store(in: &c)
            }

            if isSectionDivider {
                appState.settings.advanced.$sectionDividerStyle
                    .removeDuplicates()
                    .receive(on: DispatchQueue.main)
                    .sink { [weak self] _ in
                        self?.updateStatusItem()
                    }
                    .store(in: &c)
            }
        }

        cancellables = c
    }

    /// Updates the appearance of the status item using the current hiding state.
    private func updateStatusItem() {
        guard
            let appState,
            let button = statusItem.button
        else {
            return
        }

        if #available(macOS 27.0, *), identifier != .visible {
            // Section membership is assignment-backed on macOS 27. Publishing
            // the old divider status items creates a second Ice-looking item
            // and AppKit reserves a 16 pt slot for each one even at length 0.
            // Keep their state objects for hotkeys and toggling, but remove the
            // obsolete status items from MenuBarAgent entirely.
            removeFromMenuBar()
            constraint?.isActive = false
            if statusItem.length != 0 { statusItem.length = 0 }
            return
        }

        let font = NSFont.boldSystemFont(ofSize: NSFont.systemFontSize)
        if button.font != font { button.font = font }
        if !button.title.isEmpty { button.title = "" }
        // Avoid temporarily clearing the native button between two images.
        if #unavailable(macOS 27.0) { button.image = nil }

        switch identifier {
        case .visible:
            updateStatusItemVisibility(true)
            button.appearsDisabled = false

            let icon = appState.settings.general.iceIcon

            // We can usually just create the image directly from the icon.
            var image = switch state {
            case .showSection: icon.visible.nsImage(for: appState)
            case .hideSection: icon.hidden.nsImage(for: appState)
            }

            if
                case .custom = icon.name,
                let originalImage = image
            {
                // Custom icons need to be resized to fit inside the button.
                let originalWidth = originalImage.size.width
                let originalHeight = originalImage.size.height
                let ratio = max(originalWidth / 25, originalHeight / 17)
                let newSize = CGSize(width: originalWidth / ratio, height: originalHeight / ratio)
                image = originalImage.resized(to: newSize)
            }

            button.image = image
        case .hidden, .alwaysHidden:
            switch state {
            case .showSection:
                switch appState.settings.advanced.sectionDividerStyle {
                case .noDivider:
                    updateStatusItemVisibility(false)
                    button.appearsDisabled = true
                    button.isHighlighted = false

                    if appState.isDraggingMenuBarItem && appState.settings.advanced.showAllSectionsOnUserDrag {
                        // We still want a subtle marker between sections.
                        button.title = "|"
                    }
                case .chevron:
                    updateStatusItemVisibility(true)
                    button.appearsDisabled = false

                    button.image = switch identifier {
                    case .hidden:
                        ControlItemImage.builtin(.chevronLarge).nsImage(for: appState)
                    case .alwaysHidden:
                        ControlItemImage.builtin(.chevronSmall).nsImage(for: appState)
                    case .visible: nil
                    }
                }
            case .hideSection:
                updateStatusItemVisibility(true)
                button.appearsDisabled = true
                button.isHighlighted = false
            }
        }
    }

    /// Updates the visibility of the status item.
    ///
    /// The hidden and always-hidden control items must always be present in
    /// the menu bar, as we use their positions to determine the items in each
    /// section. Setting `statusItem.isVisible` to `false` completely removes
    /// the item. Instead, we toggle the width constraint on the item's content
    /// view, update the item's length, then adjust the content size of the
    /// item's window if needed.
    private func updateStatusItemVisibility(_ isVisible: Bool) {
        guard let appState else {
            return
        }

        if isVisible {
            constraint?.isActive = true
            let length = identifier.length(for: state)
            if statusItem.length != length { statusItem.length = length }
        } else {
            let showOnDrag = appState.settings.advanced.showAllSectionsOnUserDrag
            let isDragging = appState.isDraggingMenuBarItem

            let shouldShow = showOnDrag && isDragging

            constraint?.isActive = false
            statusItem.length = shouldShow ? 3 : 0

            if let window {
                let size = withMutableCopy(of: window.frame.size) { $0.width = shouldShow ? 3 : 1 }
                window.setContentSize(size)
            }
        }
    }

    /// Adds the control item to the menu bar.
    private func addToMenuBar() {
        if #available(macOS 27.0, *), identifier != .visible {
            return
        }
        guard !isAddedToMenuBar else {
            return
        }
        statusItem.isVisible = true
    }

    /// Removes the control item from the menu bar.
    private func removeFromMenuBar() {
        guard isAddedToMenuBar else {
            return
        }
        // Setting `statusItem.isVisible` to `false` has the unwanted side
        // effect of deleting the preferred position. Cache and restore it.
        let autosaveName = statusItem.autosaveName as String
        let cached = ControlItemDefaults[.preferredPosition, autosaveName]
        statusItem.isVisible = false
        ControlItemDefaults[.preferredPosition, autosaveName] = cached
    }

    /// Performs the control item's action.
    @objc private func performAction() {
        guard let menuBarManager = appState?.menuBarManager else { return }
        let event = NSApp.currentEvent

        let eventIsFreshButtonEvent = if
            let event,
            event.windowNumber == statusItem.button?.window?.windowNumber
        {
            ProcessInfo.processInfo.systemUptime - event.timestamp < 0.5
        } else {
            false
        }

        if eventIsFreshButtonEvent, event?.type == .rightMouseUp {
            showMenu()
            return
        }

        // The button sends its ordinary action on mouse-up on macOS 27. Accessibility
        // presses can arrive with no event, an application-defined event, or
        // NSApp's last unrelated event. Only trust modifiers from a fresh
        // mouse event that belongs to this status item's own window; otherwise
        // a preceding Command-drag can make the next press look like another
        // reorder gesture and silently discard it.
        let eventIsFreshButtonClick = eventIsFreshButtonEvent &&
            (event?.type == .leftMouseDown || event?.type == .leftMouseUp)
        let modifierFlags = eventIsFreshButtonClick ? event?.modifierFlags ?? [] : []

        // Command-click is the start of the system's native status-item
        // reorder gesture. It must not also toggle the hidden section.
        if modifierFlags.contains(.command) {
            return
        }

        if modifierFlags == .control {
            showMenu()
            return
        }

        if
            modifierFlags == .option,
            let section = menuBarManager.section(withName: .alwaysHidden),
            section.canToggleVisibility
        {
            menuBarManager.prepareForControlToggle()
            section.toggle()
            return
        }

        if
            let section = menuBarManager.section(withName: sectionName),
            section.canToggleVisibility
        {
            menuBarManager.prepareForControlToggle()
            section.toggle()
        }
    }

    /// Creates a menu to show under the control item.
    private func createMenu(with appState: AppState) -> NSMenu {
        func hotkey(withAction action: HotkeyAction) -> Hotkey? {
            appState.settings.hotkeys.hotkey(withAction: action)
        }

        let menu = NSMenu(title: "Ice")

        let settingsItem = NSMenuItem(
            title: "Ice Settings…",
            action: #selector(AppDelegate.openSettingsWindow),
            keyEquivalent: ","
        )
        settingsItem.keyEquivalentModifierMask = .command
        menu.addItem(settingsItem)

        menu.addItem(.separator())

        let searchItem = NSMenuItem(
            title: "Search Menu Bar Items",
            action: #selector(showSearchPanel),
            keyEquivalent: ""
        )
        if
            let hotkey = hotkey(withAction: .searchMenuBarItems),
            let keyCombination = hotkey.keyCombination
        {
            searchItem.keyEquivalent = keyCombination.key.keyEquivalent
            searchItem.keyEquivalentModifierMask = keyCombination.modifiers.nsEventFlags
        }
        searchItem.target = self
        if #unavailable(macOS 27.0) {
            menu.addItem(searchItem)
        }

        menu.addItem(.separator())

        // Add items to toggle the hidden and always-hidden sections.
        for name: MenuBarSection.Name in [.hidden, .alwaysHidden] {
            guard
                let section = appState.menuBarManager.section(withName: name),
                section.canToggleVisibility
            else {
                continue
            }
            let item = NSMenuItem(
                title: "\(section.isHidden ? "Show" : "Hide") \(name.displayString) Section",
                action: #selector(toggleMenuBarSection),
                keyEquivalent: ""
            )
            if
                let hotkey = section.hotkey,
                let keyCombination = hotkey.keyCombination
            {
                item.keyEquivalent = keyCombination.key.keyEquivalent
                item.keyEquivalentModifierMask = keyCombination.modifiers.nsEventFlags
            }
            item.target = self
            item.representedObject = section
            menu.addItem(item)
        }

        menu.addItem(.separator())

        let checkForUpdatesItem = NSMenuItem(
            title: "Check for Updates…",
            action: #selector(checkForUpdates),
            keyEquivalent: ""
        )
        checkForUpdatesItem.target = self
        menu.addItem(checkForUpdatesItem)

        menu.addItem(.separator())

        let quitItem = NSMenuItem(
            title: "Quit Ice",
            action: #selector(NSApp.terminate),
            keyEquivalent: "q"
        )
        quitItem.keyEquivalentModifierMask = .command
        menu.addItem(quitItem)

        return menu
    }

    /// Shows the control item's menu.
    private func showMenu() {
        guard let appState else {
            return
        }
        let menu = createMenu(with: appState)
        statusItem.showMenu(menu)
    }

    /// Toggles the menu bar section associated with the given menu item.
    @objc private func toggleMenuBarSection(for menuItem: NSMenuItem) {
        guard let section = menuItem.representedObject as? MenuBarSection else {
            return
        }
        appState?.menuBarManager.prepareForControlToggle()
        section.toggle()
    }

    /// Opens the menu bar search panel.
    @objc private func showSearchPanel() {
        appState?.menuBarManager.searchPanel.show()
    }

    /// Opens the settings window and checks for app updates.
    @objc private func checkForUpdates() {
        guard let appState else {
            return
        }
        appState.updatesManager.checkForUpdates()
    }
}

// MARK: - ControlItemDefaults

/// Proxy getters and setters for a control item's stored
/// UserDefaults values.
enum ControlItemDefaults {
    /// Accesses the value associated with the specified key
    /// and autosave name.
    static subscript<Value>(key: Key<Value>, autosaveName: String) -> Value? {
        get {
            let stringKey = key.stringKey(for: autosaveName)
            return UserDefaults.standard.object(forKey: stringKey) as? Value
        }
        set {
            let stringKey = key.stringKey(for: autosaveName)
            return UserDefaults.standard.set(newValue, forKey: stringKey)
        }
    }

    /// Migrates the given control item defaults key from an old
    /// autosave name to a new autosave name.
    static func migrate<Value>(key: Key<Value>, from oldAutosaveName: String, to newAutosaveName: String) {
        guard newAutosaveName != oldAutosaveName else {
            return
        }
        Self[key, newAutosaveName] = Self[key, oldAutosaveName]
        Self[key, oldAutosaveName] = nil
    }

    /// Performs some initial required setup work before the
    /// creation of a control item.
    @MainActor fileprivate static func preflightSetup(for controlItem: ControlItem) {
        let autosaveName = controlItem.autosaveName

        if #available(macOS 27.0, *), controlItem.identifier == .visible,
           Self[.preferredPosition, autosaveName] == nil {
            Self[.preferredPosition, autosaveName] = Self[.preferredPosition, controlItem.identifier.rawValue]
        }

        // Visible and hidden control items should be added before
        // existing items in the status bar.
        if ControlItemDefaults[.preferredPosition, autosaveName] == nil {
            switch controlItem.identifier {
            case .visible:
                ControlItemDefaults[.preferredPosition, autosaveName] = 0
            case .hidden:
                ControlItemDefaults[.preferredPosition, autosaveName] = 1
            case .alwaysHidden:
                break
            }
        }

        // The control item should be visible by default. We change
        // this after finishing setup, if needed.
        if ControlItemDefaults[.visible, autosaveName] == nil {
            ControlItemDefaults[.visible, autosaveName] = true
        }
        if
            #available(macOS 26.0, *),
            ControlItemDefaults[.visibleCC, autosaveName] == nil
        {
            ControlItemDefaults[.visibleCC, autosaveName] = true
        }
        if #available(macOS 27.0, *) {
            let isUserFacingToggle = controlItem.identifier == .visible
            ControlItemDefaults[.visible, autosaveName] = isUserFacingToggle
            ControlItemDefaults[.visibleCC, autosaveName] = isUserFacingToggle
            if
                isUserFacingToggle,
                let position = ControlItemDefaults[.preferredPosition, autosaveName],
                position <= 0
            {
                ControlItemDefaults[.preferredPosition, autosaveName] = nil
            }
        }
    }
}

// MARK: - ControlItemDefaults.Key

extension ControlItemDefaults {
    /// Keys used to look up UserDefaults values for control items.
    struct Key<Value> {
        /// The raw value of the key.
        let rawValue: String

        /// Returns the full string key for the given autosave name.
        func stringKey(for autosaveName: String) -> String {
            "NSStatusItem \(rawValue) \(autosaveName)"
        }
    }
}

// MARK: ControlItemDefaults.Key<CGFloat>
extension ControlItemDefaults.Key<CGFloat> {
    /// String key: "NSStatusItem Preferred Position autosaveName"
    static let preferredPosition = Self(rawValue: "Preferred Position")
}

// MARK: ControlItemDefaults.Key<Bool>
extension ControlItemDefaults.Key<Bool> {
    /// String key: "NSStatusItem Visible autosaveName"
    static let visible = Self(rawValue: "Visible")

    /// String key: "NSStatusItem VisibleCC autosaveName"
    static let visibleCC = Self(rawValue: "VisibleCC")
}
