//
//  ControlItem.swift
//  Ice
//

import Cocoa
import Combine

/// A status item that controls a section in the menu bar.
@MainActor
final class ControlItem {
    /// Possible identifiers for control items.
    enum Identifier: String, CaseIterable {
        case iceIcon = "SItem"
        case hidden = "HItem"
        case alwaysHidden = "AHItem"

        /// Legacy menu bar info for the control item with this identifier.
        var legacyInfo: MenuBarItemLegacyInfo {
            switch self {
            case .iceIcon: .iceIcon
            case .hidden: .hiddenControlItem
            case .alwaysHidden: .alwaysHiddenControlItem
            }
        }
    }

    /// Possible hiding states for control items.
    enum HidingState {
        case hideItems, showItems
    }

    /// Possible lengths for control items.
    enum Lengths {
        static let standard: CGFloat = NSStatusItem.variableLength
        static let expanded: CGFloat = 10_000
    }

    /// The control item's hiding state (`@Published`).
    @Published var state = HidingState.hideItems

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

    /// The shared app state.
    private weak var appState: AppState?

    /// The control item's underlying status item.
    private let statusItem: NSStatusItem

    /// A horizontal constraint for the control item's content view.
    private let constraint: NSLayoutConstraint?

    /// Storage for internal observers.
    private var cancellables = Set<AnyCancellable>()

    /// A Boolean value that indicates whether the control item serves as
    /// a divider between sections.
    var isSectionDivider: Bool {
        identifier != .iceIcon
    }

    /// A Boolean value that indicates whether the control item is currently
    /// displayed in the menu bar.
    var isAddedToMenuBar: Bool {
        statusItem.isVisible
    }

    /// The corresponding section name for the control item.
    var sectionName: MenuBarSection.Name {
        switch identifier {
        case .iceIcon: .visible
        case .hidden: .hidden
        case .alwaysHidden: .alwaysHidden
        }
    }

    /// Creates a control item with the given identifier.
    init(identifier: Identifier) {
        let autosaveName = identifier.rawValue

        // If the status item doesn't have a preferred position, set it
        // according to the identifier.
        if StatusItemDefaults[.preferredPosition, autosaveName] == nil {
            switch identifier {
            case .iceIcon:
                StatusItemDefaults[.preferredPosition, autosaveName] = 0
            case .hidden:
                StatusItemDefaults[.preferredPosition, autosaveName] = 1
            case .alwaysHidden:
                break
            }
        }

        self.statusItem = NSStatusBar.system.statusItem(withLength: 0)
        self.statusItem.autosaveName = autosaveName
        self.identifier = identifier

        if let button = statusItem.button {
            // This could break in a new macOS release, but we need this constraint in order to be
            // able to hide the control item when the `ShowSectionDividers` setting is disabled. A
            // previous implementation used the status item's `isVisible` property, which was more
            // robust, but would completely remove the control item. With the current set of
            // features, we need to be able to accurately retrieve the items for each section, so
            // we need the control item to always be present to act as a delimiter. The new solution
            // is to remove the constraint that prevents status items from having a length of zero,
            // then resize the content view. FIXME: Find a replacement for this.
            if
                let constraints = button.window?.contentView?.constraintsAffectingLayout(for: .horizontal),
                let constraint = constraints.first(where: Predicates.controlItemConstraint(button: button))
            {
                assert(constraints.filter(Predicates.controlItemConstraint(button: button)).count == 1)
                self.constraint = constraint
            } else {
                self.constraint = nil
            }

            button.target = self
            button.action = #selector(performAction)
        } else {
            self.constraint = nil
        }
    }

    /// Removes the status item without clearing its stored position.
    deinit {
        // Removing the status item has the unwanted side effect of deleting
        // the preferredPosition. Cache and restore it.
        let autosaveName = statusItem.autosaveName as String
        let cached = StatusItemDefaults[.preferredPosition, autosaveName]
        NSStatusBar.system.removeStatusItem(statusItem)
        StatusItemDefaults[.preferredPosition, autosaveName] = cached
    }

    /// Performs the initial setup of the control item.
    func performSetup(with appState: AppState) {
        self.appState = appState
        Task {
            updateStatusItem(with: state)
            Task {
                configureCancellables()
            }
        }
    }

    /// Configures the internal observers for the control item.
    private func configureCancellables() {
        var c = Set<AnyCancellable>()

        $state
            .sink { [weak self] state in
                self?.updateStatusItem(with: state)
            }
            .store(in: &c)

        statusItem.publisher(for: \.isVisible)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] isVisible in
                guard let self, let appState else {
                    return
                }

                let manager = appState.settingsManager.hotkeySettingsManager

                let hotkey: Hotkey? = switch identifier {
                case .iceIcon: nil
                case .hidden: manager.hotkey(withAction: .toggleHiddenSection)
                case .alwaysHidden: manager.hotkey(withAction: .toggleAlwaysHiddenSection)
                }

                guard let hotkey else {
                    return
                }

                if isVisible {
                    hotkey.enable()
                } else {
                    hotkey.disable()
                }
            }
            .store(in: &c)

        statusItem.publisher(for: \.button)
            .compactMap { $0 }
            .flatMap { $0.publisher(for: \.window) }
            .sink { [weak self] window in
                self?.window = window
            }
            .store(in: &c)

        $window
            .compactMap { $0 }
            .flatMap { $0.publisher(for: \.frame) }
            .sink { [weak self] frame in
                self?.frame = frame
            }
            .store(in: &c)

        $window
            .compactMap { $0 }
            .flatMap { $0.publisher(for: \.screen) }
            .sink { [weak self] screen in
                self?.screen = screen
            }
            .store(in: &c)

        Publishers.CombineLatest(
            $frame
                .compactMap { $0 },
            $screen
                .compactMap { $0 }
                .flatMap { $0.publisher(for: \.frame) }
        )
        .sink { [weak self] frame, screenFrame in
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
                .receive(on: DispatchQueue.main)
                .sink { [weak self] dragging in
                    guard let self else {
                        return
                    }
                    if dragging {
                        updateStatusItem(with: state)
                    }
                }
                .store(in: &c)

            appState.settingsManager.generalSettingsManager.$useIceBar
                .receive(on: DispatchQueue.main)
                .sink { [weak self] useIceBar in
                    guard
                        let self,
                        let button = statusItem.button
                    else {
                        return
                    }
                    if useIceBar {
                        button.sendAction(on: [.leftMouseDown, .rightMouseUp])
                    } else {
                        button.sendAction(on: [.leftMouseUp, .rightMouseUp])
                    }
                }
                .store(in: &c)

            if identifier == .iceIcon {
                appState.settingsManager.generalSettingsManager.$showIceIcon
                    .combineLatest(statusItem.publisher(for: \.isVisible))
                    .removeDuplicates { $0 == $1 }
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

                appState.settingsManager.generalSettingsManager.$iceIcon
                    .receive(on: DispatchQueue.main)
                    .sink { [weak self] _ in
                        guard let self else {
                            return
                        }
                        updateStatusItem(with: state)
                    }
                    .store(in: &c)

                appState.settingsManager.generalSettingsManager.$customIceIconIsTemplate
                    .receive(on: DispatchQueue.main)
                    .sink { [weak self] _ in
                        guard let self else {
                            return
                        }
                        updateStatusItem(with: state)
                    }
                    .store(in: &c)
            }

            if identifier == .alwaysHidden {
                appState.settingsManager.advancedSettingsManager.$enableAlwaysHiddenSection
                    .combineLatest(statusItem.publisher(for: \.isVisible))
                    .removeDuplicates { $0 == $1 }
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
                appState.settingsManager.advancedSettingsManager.$sectionDividerStyle
                    .receive(on: DispatchQueue.main)
                    .sink { [weak self] _ in
                        guard let self else {
                            return
                        }
                        updateStatusItem(with: state)
                    }
                    .store(in: &c)
            }
        }

        cancellables = c
    }

    /// Updates the appearance of the status item using the given hiding state.
    private func updateStatusItem(with state: HidingState) {
        guard
            let appState,
            let button = statusItem.button
        else {
            return
        }

        button.font = NSFont.boldSystemFont(ofSize: NSFont.systemFontSize)
        button.title = ""
        button.image = nil

        switch identifier {
        case .iceIcon:
            updateStatusItemVisibility(true, state: state)
            updateButtonEnabledState(true) // Make sure button is enabled.

            let icon = appState.settingsManager.generalSettingsManager.iceIcon

            // We can usually just create the image directly from the icon.
            var image = switch state {
            case .hideItems: icon.hidden.nsImage(for: appState)
            case .showItems: icon.visible.nsImage(for: appState)
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
            case .hideItems:
                updateStatusItemVisibility(true, state: state)
                updateButtonEnabledState(false) // Keep button from highlighting.
            case .showItems:
                switch appState.settingsManager.advancedSettingsManager.sectionDividerStyle {
                case .noDivider:
                    updateStatusItemVisibility(false, state: state)
                    updateButtonEnabledState(false) // Keep button from highlighting.

                    if appState.isDraggingMenuBarItem && appState.settingsManager.advancedSettingsManager.showAllSectionsOnUserDrag {
                        // We still want a subtle marker between sections.
                        button.title = "|"
                    }
                case .chevron:
                    updateStatusItemVisibility(true, state: state)
                    updateButtonEnabledState(true) // Make sure button is enabled.

                    button.image = switch identifier {
                    case .hidden:
                        ControlItemImage.builtin(.chevronLarge).nsImage(for: appState)
                    case .alwaysHidden:
                        ControlItemImage.builtin(.chevronSmall).nsImage(for: appState)
                    case .iceIcon: nil
                    }
                }
            }
        }
    }

    /// Updates the visibility of the status item.
    ///
    /// The control item must be present in the menu bar so that Ice can determine
    /// the items in its section. The status item's `isVisible` property completely
    /// removes the item, and therefore cannot be used. Instead, this method sets
    /// the status item's length to the appropriate value for the provided hiding
    /// state, then either enables or disables a layout constraint on the item's
    /// content view and adjusts the item's window if needed.
    private func updateStatusItemVisibility(_ isVisible: Bool, state: HidingState) {
        guard let appState else {
            return
        }
        if isVisible {
            statusItem.length = switch identifier {
            case .iceIcon: Lengths.standard
            case .hidden, .alwaysHidden:
                switch state {
                case .hideItems: Lengths.expanded
                case .showItems: Lengths.standard
                }
            }
            constraint?.isActive = true
        } else {
            let wider = appState.isDraggingMenuBarItem && appState.settingsManager.advancedSettingsManager.showAllSectionsOnUserDrag
            statusItem.length = wider ? 3 : 0
            constraint?.isActive = false
            if let window {
                var size = window.frame.size
                size.width = wider ? 3 : 1
                window.setContentSize(size)
            }
        }
    }

    /// Adds the control item to the menu bar.
    private func addToMenuBar() {
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
        // effect of deleting the preferredPosition. Cache and restore it.
        let autosaveName = statusItem.autosaveName as String
        let cached = StatusItemDefaults[.preferredPosition, autosaveName]
        statusItem.isVisible = false
        StatusItemDefaults[.preferredPosition, autosaveName] = cached
    }

    /// Updates the enabled state of the status item's button.
    private func updateButtonEnabledState(_ isEnabled: Bool) {
        guard let button = statusItem.button else {
            return
        }
        if isEnabled {
            button.cell?.isEnabled = true
        } else {
            button.cell?.isEnabled = false
            button.isHighlighted = false
        }
    }

    /// Performs the control item's action.
    @objc private func performAction() {
        guard
            let appState,
            let event = NSApp.currentEvent
        else {
            return
        }

        switch event.type {
        case .leftMouseDown, .leftMouseUp:
            if NSEvent.modifierFlags == .control {
                showMenu()
                return
            }

            let targetSection: MenuBarSection

            if
                NSEvent.modifierFlags == .option,
                let alwaysHiddenSection = appState.menuBarManager.section(withName: .alwaysHidden),
                alwaysHiddenSection.isEnabled
            {
                targetSection = alwaysHiddenSection
            } else if
                let section = appState.menuBarManager.section(withName: sectionName),
                section.isEnabled
            {
                targetSection = section
            } else {
                return
            }

            Task {
                await targetSection.toggle()
            }
        case .rightMouseUp:
            showMenu()
        default:
            return
        }
    }

    /// Creates a menu to show under the control item.
    private func createMenu(with appState: AppState) -> NSMenu {
        func hotkey(withAction action: HotkeyAction) -> Hotkey? {
            let hotkeySettingsManager = appState.settingsManager.hotkeySettingsManager
            return hotkeySettingsManager.hotkey(withAction: action)
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
        searchItem.target = self
        if
            let hotkey = hotkey(withAction: .searchMenuBarItems),
            let keyCombination = hotkey.keyCombination
        {
            searchItem.keyEquivalent = keyCombination.key.keyEquivalent
            searchItem.keyEquivalentModifierMask = keyCombination.modifiers.nsEventFlags
        }
        menu.addItem(searchItem)

        menu.addItem(.separator())

        // Add menu items to toggle the hidden and always-hidden sections.
        let sectionNames: [MenuBarSection.Name] = [.hidden, .alwaysHidden]
        for name in sectionNames {
            guard
                let section = appState.menuBarManager.section(withName: name),
                section.controlItem.isAddedToMenuBar
            else {
                // Section doesn't exist, or is disabled.
                continue
            }
            let item = NSMenuItem(
                title: "\(section.isHidden ? "Show" : "Hide") the \(name.displayString) Section",
                action: #selector(toggleMenuBarSection),
                keyEquivalent: ""
            )
            item.target = self
            item.representedObject = section
            switch name {
            case .visible:
                break
            case .hidden:
                if
                    let hotkey = hotkey(withAction: .toggleHiddenSection),
                    let keyCombination = hotkey.keyCombination
                {
                    item.keyEquivalent = keyCombination.key.keyEquivalent
                    item.keyEquivalentModifierMask = keyCombination.modifiers.nsEventFlags
                }
            case .alwaysHidden:
                if
                    let hotkey = hotkey(withAction: .toggleAlwaysHiddenSection),
                    let keyCombination = hotkey.keyCombination
                {
                    item.keyEquivalent = keyCombination.key.keyEquivalent
                    item.keyEquivalentModifierMask = keyCombination.modifiers.nsEventFlags
                }
            }
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
        Task {
            await section.toggle()
        }
    }

    /// Opens the menu bar search panel.
    @objc private func showSearchPanel() {
        guard
            let appState,
            let screen = MenuBarSearchPanel.defaultScreen
        else {
            return
        }
        Task {
            await appState.menuBarManager.searchPanel.show(on: screen)
        }
    }

    /// Opens the settings window and checks for app updates.
    @objc private func checkForUpdates() {
        guard let appState else {
            return
        }
        appState.updatesManager.checkForUpdates()
    }
}
