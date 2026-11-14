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

    /// Length of an expanded hiding spacer.
    ///
    /// On macOS 27 a spacer wider than half the screen is dropped instead of
    /// pushing its neighbours into overflow, so the width comes from
    /// ``MenuBarSpacerPlan``. Older systems keep the 10 000 trick.
    private func expandedHidingLength() -> CGFloat {
        if #available(macOS 27, *) {
            return MenuBarSpacerPlan.current().length
        }
        return Lengths.expanded
    }

    /// Accessibility identifier prefix of the blank items that extend a spacer.
    static let spacerExtensionIdentifier = "IceSpacerExtension"

    /// Blank items placed right next to this divider while its section is
    /// hidden, for screens too wide for one spacer (macOS 27).
    ///
    /// They are created on hide and removed on show. Removing an item also
    /// deletes its stored order key, so each new set is seeded again from
    /// ``spacerHint`` and lands in the same slot.
    private var spacerExtensions = [NSStatusItem]()

    /// The placement of the spacer extensions that is still running.
    private var spacerTask: Task<Void, Never>?

    /// Bumped whenever the extensions are torn down, so a stale placement
    /// task stops instead of adding items to a section that is now shown.
    private var spacerGeneration = 0

    /// Whether placement already ran for the current hide, successfully or
    /// not, so it isn't retried on every state update.
    private var spacerPlacementSettled = false

    /// The order key that puts an item directly left of this divider.
    ///
    /// Found by probing (see ``findSpacerHint(reference:generation:)``) and
    /// kept until it stops landing next to the divider, which means the user
    /// moved it.
    private var spacerHint: CGFloat? {
        get {
            (UserDefaults.standard.object(forKey: "SpacerHint.\(statusItem.autosaveName as String)") as? NSNumber)
                .map { CGFloat($0.doubleValue) }
        }
        set {
            UserDefaults.standard.set(newValue.map(Double.init), forKey: "SpacerHint.\(statusItem.autosaveName as String)")
        }
    }

    /// The control item's hiding state (`@Published`).
    @Published var state = HidingState.hideItems

    /// A Boolean value that indicates whether the control item is visible (`@Published`).
    @Published var isVisible = true

    /// The frame of the control item's window (`@Published`).
    @Published private(set) var windowFrame: CGRect?

    /// The shared app state.
    private weak var appState: AppState?

    /// The control item's underlying status item.
    private let statusItem: NSStatusItem

    /// A horizontal constraint for the control item's content view.
    private let constraint: NSLayoutConstraint?

    /// The control item's identifier.
    private let identifier: Identifier

    /// Storage for internal observers.
    private var cancellables = Set<AnyCancellable>()

    /// The menu bar section associated with the control item.
    private weak var section: MenuBarSection? {
        appState?.menuBarManager.sections.first { $0.controlItem === self }
    }

    /// The control item's window.
    var window: NSWindow? {
        statusItem.button?.window
    }

    /// The identifier of the control item's window.
    var windowID: CGWindowID? {
        guard let window else {
            return nil
        }
        // windowNumber is Int and traps on overflow with the non-failable
        // initializer on macOS 26 (see jordanbaird/Ice#580, #977).
        return CGWindowID(exactly: window.windowNumber)
    }

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

    /// Creates a control item with the given identifier and app state.
    init(identifier: Identifier, appState: AppState) {
        let autosaveName = identifier.rawValue

        // If the status item doesn't have a preferred position, set it
        // according to the identifier.
        if StatusItemDefaults[.preferredPosition, autosaveName] == nil {
            if #available(macOS 27, *) {
                StatusItemDefaults[.preferredPosition, autosaveName] = MenuBarOrderHints.freshSeed(for: identifier)
            } else {
                switch identifier {
                case .iceIcon:
                    StatusItemDefaults[.preferredPosition, autosaveName] = 0
                case .hidden:
                    StatusItemDefaults[.preferredPosition, autosaveName] = 1
                case .alwaysHidden:
                    // Lower values sit further right, so the always-hidden
                    // divider defaults left of the hidden divider.
                    StatusItemDefaults[.preferredPosition, autosaveName] = 2
                }
            }
        }

        self.statusItem = NSStatusBar.system.statusItem(withLength: 0)
        self.statusItem.autosaveName = autosaveName
        self.identifier = identifier
        self.appState = appState

        // This could break in a new macOS release, but we need this constraint in order to be
        // able to hide the control item when the `ShowSectionDividers` setting is disabled. A
        // previous implementation used the status item's `isVisible` property, which was more
        // robust, but would completely remove the control item. With the current set of
        // features, we need to be able to accurately retrieve the items for each section, so
        // we need the control item to always be present to act as a delimiter. The new solution
        // is to remove the constraint that prevents status items from having a length of zero,
        // then resize the content view. FIXME: Find a replacement for this.
        if
            let button = statusItem.button,
            let constraints = button.window?.contentView?.constraintsAffectingLayout(for: .horizontal),
            let constraint = constraints.first(where: Predicates.controlItemConstraint(button: button))
        {
            assert(constraints.filter(Predicates.controlItemConstraint(button: button)).count == 1)
            self.constraint = constraint
        } else {
            self.constraint = nil
        }

        configureStatusItem()
    }

    /// Removes the status item without clearing its stored position.
    deinit {
        for item in spacerExtensions {
            let name = item.autosaveName as String
            NSStatusBar.system.removeStatusItem(item)
            StatusItemDefaults[.preferredPosition, name] = nil
            StatusItemDefaults[.visible, name] = nil
            UserDefaults.standard.removeObject(forKey: "NSStatusItem VisibleCC \(name)")
        }
        // Removing the status item has the unwanted side effect of deleting
        // the preferredPosition. Cache and restore it.
        let autosaveName = statusItem.autosaveName as String
        let cached = StatusItemDefaults[.preferredPosition, autosaveName]
        NSStatusBar.system.removeStatusItem(statusItem)
        StatusItemDefaults[.preferredPosition, autosaveName] = cached
    }

    /// Configures the internal observers for the control item.
    private func configureCancellables() {
        var c = Set<AnyCancellable>()

        $state
            .sink { [weak self] state in
                self?.updateStatusItem(with: state)
            }
            .store(in: &c)

        Publishers.CombineLatest($isVisible, $state)
            .sink { [weak self] (isVisible, state) in
                guard
                    let self,
                    let section
                else {
                    return
                }
                applyLength(isVisible: isVisible, state: state, section: section.name)
                scheduleSpacerUpdate()
                if identifier == .hidden {
                    // The always-hidden divider only extends while this one
                    // is shown.
                    appState?.menuBarManager.section(withName: .alwaysHidden)?.controlItem.scheduleSpacerUpdate()
                }
            }
            .store(in: &c)

        // The attached screens decide between spacers and the concealer, and
        // size the spacers; refit when a display is added, removed or changes
        // resolution.
        NotificationCenter.default.publisher(for: NSApplication.didChangeScreenParametersNotification)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                guard
                    let self,
                    isSectionDivider,
                    let section
                else {
                    return
                }
                // Start over: the new screen may need more, fewer or no extensions.
                removeSpacerExtensions()
                updateStatusItem(with: state)
                applyLength(isVisible: isVisible, state: state, section: section.name)
                scheduleSpacerUpdate()
            }
            .store(in: &c)

        // An extension still in the bar when Ice quits would keep its order
        // key; removing it deletes the key.
        NotificationCenter.default.publisher(for: NSApplication.willTerminateNotification)
            .sink { [weak self] _ in
                self?.removeSpacerExtensions()
            }
            .store(in: &c)

        constraint?.publisher(for: \.isActive)
            .removeDuplicates()
            .sink { [weak self] isActive in
                self?.isVisible = isActive
            }
            .store(in: &c)

        statusItem.publisher(for: \.isVisible)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] isVisible in
                guard
                    let self,
                    let appState,
                    let section
                else {
                    return
                }

                // A disabled section must not leave blank extensions behind.
                scheduleSpacerUpdate()

                let manager = appState.settingsManager.hotkeySettingsManager

                let hotkey: Hotkey? = switch section.name {
                case .visible: nil
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

        window?.publisher(for: \.frame)
            .sink { [weak self] frame in
                guard
                    let self,
                    let screen = window?.screen,
                    screen.frame.intersects(frame)
                else {
                    return
                }
                windowFrame = frame
            }
            .store(in: &c)

        if let appState {
            appState.settingsManager.generalSettingsManager.$showIceIcon
                .receive(on: DispatchQueue.main)
                .sink { [weak self] showIceIcon in
                    guard
                        let self,
                        !isSectionDivider
                    else {
                        return
                    }
                    if showIceIcon {
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

            appState.settingsManager.generalSettingsManager.$reverseIceIcon
                .receive(on: DispatchQueue.main)
                .sink { [weak self] _ in
                    guard let self else {
                        return
                    }
                    updateStatusItem(with: state)
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

            appState.settingsManager.advancedSettingsManager.$showSectionDividers
                .receive(on: DispatchQueue.main)
                .sink { [weak self] shouldShow in
                    guard
                        let self,
                        isSectionDivider,
                        state == .showItems || MenuBarConcealer.isInUse
                    else {
                        return
                    }
                    // ponytail: the divider collapses to a 1pt sliver instead of
                    // disappearing, so it stays in the bar as the section
                    // boundary (AX lookup still finds it) without holding a slot.
                    isVisible = shouldShow
                }
                .store(in: &c)

            appState.settingsManager.advancedSettingsManager.$enableAlwaysHiddenSection
                .receive(on: DispatchQueue.main)
                .sink { [weak self] enable in
                    guard
                        let self,
                        identifier == .alwaysHidden,
                        let visibleSection = appState.menuBarManager.section(withName: .visible)
                    else {
                        return
                    }
                    if enable {
                        addToMenuBar()
                    } else {
                        removeFromMenuBar()
                    }
                    // The Ice icon mirrors this section; repaint its arrow
                    // now that the source has changed.
                    visibleSection.controlItem.updateStatusItem(with: visibleSection.controlItem.state)
                }
                .store(in: &c)
        }

        cancellables = c
    }

    /// Sets the status item's length for the given visibility and state.
    private func applyLength(isVisible: Bool, state: HidingState, section: MenuBarSection.Name) {
        if isVisible {
            statusItem.length = switch section {
            case .visible: Lengths.standard
            case .hidden, .alwaysHidden:
                switch state {
                // The concealer hides sections without a spacer.
                case .hideItems: MenuBarConcealer.isInUse ? Lengths.standard : expandedHidingLength()
                case .showItems: Lengths.standard
                }
            }
            constraint?.isActive = true
        } else {
            statusItem.length = 0
            constraint?.isActive = false
            if let window {
                var size = window.frame.size
                size.width = 1
                window.setContentSize(size)
            }
        }
    }

    /// Sets the initial configuration for the status item.
    private func configureStatusItem() {
        defer {
            configureCancellables()
            updateStatusItem(with: state)
        }
        if isSectionDivider {
            clearLeftoverExtensionDefaults()
        }
        guard let button = statusItem.button else {
            return
        }
        button.target = self
        button.action = #selector(performAction)
        // AX identifier for the divider so its position can be looked up via
        // Accessibility (MenuBarItemAXDiscovery.dividerFrames): on macOS 27
        // button.window.frame returns the spacer's rect, not the chevron's
        // position, so the Ice Bar can't use it to classify sections.
        switch identifier {
        case .hidden:
            button.setAccessibilityIdentifier("IceHiddenDivider")
        case .alwaysHidden:
            button.setAccessibilityIdentifier("IceAlwaysHiddenDivider")
        case .iceIcon:
            break
        }
    }

    /// Updates the appearance of the status item using the given hiding state.
    func updateStatusItem(with state: HidingState) {
        guard
            let appState,
            let section,
            let button = statusItem.button
        else {
            return
        }

        switch section.name {
        case .visible:
            isVisible = true
            // Enable the cell, as it may have been previously disabled.
            button.cell?.isEnabled = true
            let icon = appState.settingsManager.generalSettingsManager.iceIcon
            let reversed = appState.settingsManager.generalSettingsManager.reverseIceIcon
            let hiddenImage = reversed ? icon.visible : icon.hidden
            let visibleImage = reversed ? icon.hidden : icon.visible
            // Closed points right like a collapsed disclosure; open points
            // left toward the revealed items, matching the section dividers.
            // The arrow mirrors the always-hidden section while it is enabled;
            // otherwise it mirrors this section.
            let alwaysHiddenSection = appState.menuBarManager.section(withName: .alwaysHidden)
            let showsOpenArrow = if alwaysHiddenSection?.isEnabled == true {
                alwaysHiddenSection?.controlItem.state == .showItems
            } else {
                state == .showItems
            }
            button.image = showsOpenArrow ? hiddenImage.nsImage(for: appState) : visibleImage.nsImage(for: appState)
            if
                case .custom = icon.name,
                let originalImage = button.image
            {
                // Custom icons need to be resized to fit inside the button.
                let originalWidth = originalImage.size.width
                let originalHeight = originalImage.size.height
                let ratio = max(originalWidth / 25, originalHeight / 17)
                let newSize = CGSize(width: originalWidth / ratio, height: originalHeight / ratio)
                button.image = originalImage.resized(to: newSize)
            }
        case .hidden, .alwaysHidden:
            // When the concealer hides sections (macOS 27 with a display
            // without a notch), a hidden section's divider keeps its shown
            // look: it only marks the boundary.
            switch MenuBarConcealer.isInUse ? .showItems : state {
            case .hideItems:
                isVisible = true
                // Prevent the cell from highlighting while expanded.
                button.cell?.isEnabled = false
                // Cell still sometimes briefly flashes on expansion unless manually unhighlighted.
                button.isHighlighted = false
                button.image = nil
            case .showItems:
                let shouldShowDivider = appState.settingsManager.advancedSettingsManager.showSectionDividers
                // ponytail: same sliver collapse as the $showSectionDividers sink
                // — a `Lengths.standard` item with no image left a ~40pt gap
                // between the revealed section and the next one.
                isVisible = shouldShowDivider
                // Enable the cell, as it may have been previously disabled.
                button.cell?.isEnabled = true
                // Set the image based on the section name and the hiding state.
                switch section.name {
                case .hidden:
                    button.image = shouldShowDivider
                        ? ControlItemImage.builtin(.chevronLarge).nsImage(for: appState)
                        : nil
                case .alwaysHidden:
                    button.image = shouldShowDivider
                        ? ControlItemImage.builtin(.chevronSmall).nsImage(for: appState)
                        : nil
                case .visible: break
                }
            }
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
                statusItem.showMenu(createMenu(with: appState))
            } else if
                NSEvent.modifierFlags == .option,
                appState.settingsManager.advancedSettingsManager.canToggleAlwaysHiddenSection
            {
                if let alwaysHiddenSection = appState.menuBarManager.section(withName: .alwaysHidden) {
                    alwaysHiddenSection.toggle()
                }
            } else if
                identifier == .iceIcon,
                let alwaysHiddenSection = appState.menuBarManager.section(withName: .alwaysHidden),
                alwaysHiddenSection.isEnabled
            {
                // The Ice icon drives the always-hidden section, leaving the
                // hidden section untouched (it is driven by click/hover/scroll
                // on empty menu bar space, its divider, or its hotkey).
                alwaysHiddenSection.toggle()
            } else {
                section?.toggle()
            }
        case .rightMouseUp:
            statusItem.showMenu(createMenu(with: appState))
        default:
            break
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
            Self.sectionStorage.weakSet(section, for: item)
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

    /// Toggles the menu bar section associated with the given menu item.
    @objc private func toggleMenuBarSection(for menuItem: NSMenuItem) {
        Self.sectionStorage.value(for: menuItem)?.toggle()
    }

    /// Opens the settings window and checks for app updates.
    @objc private func checkForUpdates() {
        guard let appState else {
            return
        }
        appState.updatesManager.checkForUpdates()
    }

    /// Adds the control item to the menu bar.
    func addToMenuBar() {
        guard !isAddedToMenuBar else {
            return
        }
        statusItem.isVisible = true
    }

    /// Removes the control item from the menu bar.
    func removeFromMenuBar() {
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

    /// Whether this divider should be extended right now.
    ///
    /// Only the outermost hidden divider needs it: when the Hidden section is
    /// hidden, everything left of it (the always-hidden divider included)
    /// already overflows with it.
    private var wantsSpacerExtensions: Bool {
        guard
            isSectionDivider,
            isAddedToMenuBar,
            isVisible,
            state == .hideItems,
            !MenuBarConcealer.isInUse
        else {
            return false
        }
        if
            identifier == .alwaysHidden,
            appState?.menuBarManager.section(withName: .hidden)?.controlItem.state == .hideItems
        {
            return false
        }
        return true
    }

    /// Updates the spacer extensions on the next run loop pass.
    ///
    /// `@Published` sinks run before the new value is stored, so reading
    /// `state` or `isVisible` inside one still returns the old value.
    func scheduleSpacerUpdate() {
        DispatchQueue.main.async { [weak self] in
            self?.updateSpacerExtensions()
        }
    }

    /// Adds or removes the blank items that extend this divider's spacer.
    ///
    /// Only macOS 27 needs them, and only while the section is hidden on a
    /// screen too wide for one spacer (``MenuBarSpacerPlan``).
    private func updateSpacerExtensions() {
        guard #available(macOS 27, *) else {
            return
        }
        let plan = MenuBarSpacerPlan.current()
        guard wantsSpacerExtensions, plan.count > 1 else {
            removeSpacerExtensions()
            return
        }
        guard spacerTask == nil, !spacerPlacementSettled else {
            // Running or done for this hide. A screen change starts over
            // through `removeSpacerExtensions()`.
            return
        }
        let generation = spacerGeneration
        spacerTask = Task { [weak self] in
            await self?.placeSpacerExtensions(length: plan.length, generation: generation)
            guard let self, generation == spacerGeneration else {
                return
            }
            spacerTask = nil
            spacerPlacementSettled = true
        }
    }

    /// What a probe is compared with, on the display whose layout
    /// Accessibility reports.
    ///
    /// Status items appear on every display, and each display moves its own
    /// overflow out of sight, but Accessibility only reports positions on one
    /// of them: the primary display (measured on macOS 27.2).
    private enum SpacerReference {
        /// The divider is drawn there, at this frame.
        case divider(CGRect)
        /// The divider overflows there but fits on another display. Everything
        /// left of it overflows with it, so a probe that gets drawn on this
        /// display sits right of the divider, and one that doesn't sits left.
        case overflowed
    }

    /// The side of the divider a probe landed on.
    private enum ProbeSide {
        case left, right
    }

    /// How a divider gets extended: what probes compare with, and the
    /// lengths of the blank items, nearest the divider first.
    private struct SpacerLayout {
        var reference: SpacerReference
        var lengths: [CGFloat]
    }

    /// Puts blank items directly next to this divider and widens them.
    ///
    /// Skipped when the divider already overflows on every display. Otherwise
    /// each item is first added one point wide, checked to sit right next to
    /// the divider, and only then widened, so a misplaced item can never
    /// blank out the wrong icons.
    private func placeSpacerExtensions(length: CGFloat, generation: Int) async {
        // Let the divider's new length settle before measuring it.
        try? await Task.sleep(for: .milliseconds(300))
        guard
            generation == spacerGeneration,
            let dividerID = dividerAccessibilityIdentifier,
            let layout = await spacerLayout(dividerID: dividerID, length: length, generation: generation)
        else {
            return
        }
        let reference = layout.reference
        var hint = spacerHint
        if let cached = hint, await !isAdjacentHint(cached, reference: reference, generation: generation) {
            hint = nil
        }
        if hint == nil {
            guard
                let found = await findSpacerHint(reference: reference, generation: generation),
                generation == spacerGeneration
            else {
                if generation == spacerGeneration {
                    discardExtensionItems()
                    Logger.controlItem.error("Couldn't place a spacer extension next to \(dividerID)")
                }
                return
            }
            // The search can stop exactly on the divider's own key, and macOS
            // orders equal keys unpredictably; nudge past it. The search has
            // already seen the key just below land right of the divider.
            let nudged = found + MenuBarOrderHints.probePrecision / 2
            guard await isAdjacentHint(nudged, reference: reference, generation: generation, checkBelow: false) else {
                if generation == spacerGeneration {
                    discardExtensionItems()
                    Logger.controlItem.error("Spacer extension for \(dividerID) didn't land next to it")
                }
                return
            }
            spacerHint = nudged
            hint = nudged
        }
        guard generation == spacerGeneration, let hint else {
            return
        }
        // Any further items stack directly left of the first one.
        for index in 1..<max(layout.lengths.count, 1) {
            _ = await placeExtension(index: index, hint: hint + 0.0001 * CGFloat(index), generation: generation)
        }
        guard generation == spacerGeneration else {
            return
        }
        for (item, itemLength) in zip(spacerExtensions, layout.lengths) {
            item.length = itemLength
        }
        Logger.controlItem.info("Extended \(dividerID) with \(layout.lengths), hint \(hint)")
    }

    /// Works out how to extend the divider, or `nil` when no display needs it.
    private func spacerLayout(dividerID: String, length: CGFloat, generation: Int) async -> SpacerLayout? {
        for _ in 0..<4 {
            guard generation == spacerGeneration else {
                return nil
            }
            guard
                let frame = await Self.ownElementFrame(dividerID),
                Self.isOnScreen(frame)
            else {
                return await overflowedSpacerLayout(dividerID: dividerID, length: length)
            }
            // An overflowed spacer can still report a plausible frame for a
            // moment, so ask what is actually drawn at its center.
            if await Self.isDrawnByIce(at: CGPoint(x: frame.midX, y: frame.midY)) {
                let center = CGPoint(x: frame.midX, y: frame.midY)
                let bounds = NSScreen.screens.lazy.map { CGDisplayBounds($0.displayID) }.first { $0.contains(center) }
                let lengths = MenuBarSpacerPlan.extensionLengths(
                    dividerLength: length,
                    visibleWidth: (bounds?.maxX ?? frame.maxX) - frame.maxX,
                    targets: NSScreen.screens.map(MenuBarSpacerPlan.Screen.init)
                )
                guard !lengths.isEmpty else {
                    return nil
                }
                Logger.controlItem.info("\(dividerID) fits on screen (\(frame.debugDescription)); extending it")
                return SpacerLayout(reference: .divider(frame), lengths: lengths)
            }
            try? await Task.sleep(for: .milliseconds(200))
        }
        return nil
    }

    /// How to extend a divider that overflows on the primary display, for
    /// the other displays, or `nil` when none of them shows it.
    private func overflowedSpacerLayout(dividerID: String, length: CGFloat) async -> SpacerLayout? {
        let others = NSScreen.screens.dropFirst().map(MenuBarSpacerPlan.Screen.init)
        guard
            MenuBarSpacerPlan.count(for: others, length: length) > 1,
            let primary = await Self.primaryStatusItems()
        else {
            return nil
        }
        guard primary.hasRoomForProbes else {
            Logger.controlItem.info("\(dividerID) overflows on the primary display, which is too full to probe")
            return nil
        }
        let lengths = MenuBarSpacerPlan.extensionLengths(
            dividerLength: length,
            visibleWidth: primary.visibleWidth,
            targets: others
        )
        guard !lengths.isEmpty else {
            return nil
        }
        Logger.controlItem.info("\(dividerID) overflows on the primary display; extending it for the others")
        return SpacerLayout(reference: .overflowed, lengths: lengths)
    }

    /// Which side of the divider a probe landed on, from the probe's frame on
    /// the reported display (`nil` when it isn't drawn there).
    private static func side(of probe: CGRect?, reference: SpacerReference) -> ProbeSide {
        switch reference {
        case .divider(let divider):
            // A probe that isn't drawn went into overflow, which only ever
            // happens left of a divider that is drawn.
            guard let probe else {
                return .left
            }
            return probe.midX < divider.minX ? .left : .right
        case .overflowed:
            return probe == nil ? .left : .right
        }
    }

    /// Places the first extension at `hint` and checks it sits right next to
    /// the divider. The extension stays in place either way.
    ///
    /// With the divider overflowed on the reported display, adjacency can't
    /// be seen directly. It follows from the key just below `hint` landing
    /// right of the divider and `hint` itself landing left: nothing else sits
    /// that close to the divider's key. `checkBelow` skips the first half when
    /// the search has just seen it.
    private func isAdjacentHint(
        _ hint: CGFloat,
        reference: SpacerReference,
        generation: Int,
        checkBelow: Bool = true
    ) async -> Bool {
        switch reference {
        case .divider(let divider):
            guard let frame = await placeExtension(index: 0, hint: hint, generation: generation) else {
                return false
            }
            return Self.isDirectlyLeft(of: divider, frame)
        case .overflowed:
            if checkBelow {
                let below = await placeExtension(index: 0, hint: hint - 2 * MenuBarOrderHints.probePrecision, generation: generation)
                guard generation == spacerGeneration, Self.side(of: below, reference: reference) == .right else {
                    return false
                }
            }
            let frame = await placeExtension(index: 0, hint: hint, generation: generation)
            return generation == spacerGeneration && Self.side(of: frame, reference: reference) == .left
        }
    }

    /// Finds the order key at the divider's left edge.
    ///
    /// Ice may not read the keys macOS stores, so it probes instead: one
    /// narrow item is re-added with different seeds and its side of the
    /// divider checked. Larger keys sit further left, so a doubling search
    /// followed by bisection converges in about 25 placements. Returns the
    /// smallest key seen landing left.
    private func findSpacerHint(reference: SpacerReference, generation: Int) async -> CGFloat? {
        func landsLeft(_ hint: CGFloat) async -> Bool? {
            let frame = await placeExtension(index: 0, hint: hint, generation: generation)
            guard generation == spacerGeneration else {
                return nil
            }
            return Self.side(of: frame, reference: reference) == .left
        }
        var low: CGFloat = 0
        var high: CGFloat?
        var probe: CGFloat = 1
        while high == nil, probe <= MenuBarOrderHints.probeLimit {
            guard let isLeft = await landsLeft(probe) else {
                return nil
            }
            if isLeft {
                high = probe
            } else {
                low = probe
                probe *= 2
            }
        }
        guard var high else {
            return nil
        }
        while high - low > MenuBarOrderHints.probePrecision {
            let middle = (low + high) / 2
            guard let isLeft = await landsLeft(middle) else {
                return nil
            }
            if isLeft {
                high = middle
            } else {
                low = middle
            }
        }
        return high
    }

    /// Adds (or re-adds) one narrow extension seeded with `hint` and returns
    /// its frame on the reported display, or `nil` if it isn't drawn there
    /// (overflowed) or the task went stale.
    private func placeExtension(index: Int, hint: CGFloat, generation: Int) async -> CGRect? {
        guard generation == spacerGeneration else {
            return nil
        }
        if index < spacerExtensions.count {
            // Removing deletes the stored key, so the new seed takes effect.
            removeExtensionItem(spacerExtensions.remove(at: index))
        }
        // A fresh name every time: an item re-added under the name of one
        // removed a moment ago briefly reports the old item's frame. The
        // counter persists so a key left behind by a crash is never reused
        // (a stored key would win over the seed).
        let serial = UserDefaults.standard.integer(forKey: Self.extensionSerialKey) &+ 1
        UserDefaults.standard.set(serial, forKey: Self.extensionSerialKey)
        let name = "\(statusItem.autosaveName as String).Spacer\(index).\(serial)"
        let accessibilityID = "\(Self.spacerExtensionIdentifier).\(name)"
        StatusItemDefaults[.preferredPosition, name] = hint
        let item = NSStatusBar.system.statusItem(withLength: 1)
        item.autosaveName = name
        if let button = item.button {
            button.title = ""
            button.image = nil
            button.isEnabled = false
            button.setAccessibilityIdentifier(accessibilityID)
        }
        spacerExtensions.insert(item, at: min(index, spacerExtensions.count))
        // macOS first reports a placeholder frame off the bar; a drawn item
        // gets its real slot within about 200ms, an overflowed one never.
        for _ in 0..<20 {
            try? await Task.sleep(for: .milliseconds(20))
            guard generation == spacerGeneration else {
                return nil
            }
            if let frame = await Self.ownElementFrame(accessibilityID), frame.width > 0, Self.isInMenuBar(frame) {
                return frame
            }
        }
        return nil
    }

    /// Stops any placement and removes the extensions, ready for the next hide.
    private func removeSpacerExtensions() {
        spacerGeneration += 1
        spacerTask?.cancel()
        spacerTask = nil
        spacerPlacementSettled = false
        discardExtensionItems()
    }

    /// Removes the blank extension items and their stored keys.
    private func discardExtensionItems() {
        for item in spacerExtensions {
            removeExtensionItem(item)
        }
        spacerExtensions.removeAll()
    }

    /// Removes one extension item and the defaults AppKit keeps for it.
    private func removeExtensionItem(_ item: NSStatusItem) {
        let name = item.autosaveName as String
        NSStatusBar.system.removeStatusItem(item)
        Self.clearExtensionDefaults(name: name)
    }

    /// Defaults key of the counter that names extension items.
    private static let extensionSerialKey = "SpacerExtensionSerial"

    /// Clears the defaults AppKit keeps for one extension item.
    private static func clearExtensionDefaults(name: String) {
        StatusItemDefaults[.preferredPosition, name] = nil
        StatusItemDefaults[.visible, name] = nil
        UserDefaults.standard.removeObject(forKey: "NSStatusItem VisibleCC \(name)")
    }

    /// Clears defaults left by extension items of an earlier run that ended
    /// without removing them (a crash).
    private func clearLeftoverExtensionDefaults() {
        let marker = " \(statusItem.autosaveName as String).Spacer"
        for key in UserDefaults.standard.dictionaryRepresentation().keys
        where key.hasPrefix("NSStatusItem ") && key.contains(marker) {
            UserDefaults.standard.removeObject(forKey: key)
        }
    }

    /// The status items drawn on the primary display, while a divider
    /// overflows there: every drawn item sits right of it.
    ///
    /// - `visibleWidth`: from the leftmost drawn item to the screen edge.
    /// - `hasRoomForProbes`: whether clear room is left of those items.
    ///   Probing relies on the divider being the first item that doesn't fit.
    ///   On a full notched screen an icon right of the divider can overflow
    ///   first, and the search would then stop next to that icon instead.
    private static func primaryStatusItems() async -> (visibleWidth: CGFloat, hasRoomForProbes: Bool)? {
        guard let screen = NSScreen.screens.first else {
            return nil
        }
        let apps = NSWorkspace.shared.runningApplications
        let bounds = CGDisplayBounds(screen.displayID)
        // The notch's right edge; status items never sit left of it.
        let notchEdge = screen.auxiliaryTopRightArea.map { bounds.minX + $0.minX - screen.frame.minX }
        return await Task.detached(priority: .userInitiated) {
            let leftmost = MenuBarItemAXDiscovery.discoverItems(in: apps)
                .compactMap(\.axFrame)
                .filter { frame in
                    frame.width > 0
                        && frame.minX >= (notchEdge ?? bounds.minX) - 1
                        && frame.maxX <= bounds.maxX + 1
                        && frame.minY >= bounds.minY - 1
                        && frame.minY < bounds.minY + 40
                }
                .map(\.minX)
                .min()
            guard let leftmost else {
                return nil
            }
            // Without a notch the app menus leave far more room than any
            // icon needs.
            let hasRoom = notchEdge.map { leftmost - $0 >= MenuBarSpacerPlan.minimumProbeRoom } ?? true
            return (bounds.maxX - leftmost, hasRoom)
        }.value
    }

    /// The Accessibility identifier set on this divider's button.
    private var dividerAccessibilityIdentifier: String? {
        switch identifier {
        case .hidden: "IceHiddenDivider"
        case .alwaysHidden: "IceAlwaysHiddenDivider"
        case .iceIcon: nil
        }
    }

    /// Reads the frame of one of Ice's own elements off the main thread
    /// (an Accessibility call into our own process from the main thread
    /// would wait on itself).
    private static func ownElementFrame(_ identifier: String) async -> CGRect? {
        await Task.detached(priority: .userInitiated) {
            MenuBarItemAXDiscovery.ownElementFrames()[identifier]
        }.value
    }

    /// Whether the element drawn at `point` (AX coordinates) belongs to Ice.
    ///
    /// Runs off the main thread: the answer may come from our own process.
    private static func isDrawnByIce(at point: CGPoint) async -> Bool {
        await Task.detached(priority: .userInitiated) {
            let systemWide = AXUIElementCreateSystemWide()
            AXUIElementSetMessagingTimeout(systemWide, 1)
            var element: AXUIElement?
            guard
                AXUIElementCopyElementAtPosition(systemWide, Float(point.x), Float(point.y), &element) == .success,
                let element
            else {
                return false
            }
            var pid: pid_t = 0
            AXUIElementGetPid(element, &pid)
            return pid == ProcessInfo.processInfo.processIdentifier
        }.value
    }

    /// Whether a frame (AX coordinates) lies in some display's menu bar strip.
    private static func isInMenuBar(_ frame: CGRect) -> Bool {
        NSScreen.screens.contains { screen in
            let bounds = CGDisplayBounds(screen.displayID)
            return frame.minX >= bounds.minX - 1
                && frame.minX < bounds.maxX
                && frame.minY >= bounds.minY - 1
                && frame.minY < bounds.minY + 40
        }
    }

    /// Whether a frame is fully on a display's menu bar, i.e. really drawn
    /// rather than parked in overflow (overflowed spacers report frames that
    /// run past the screen edge or below the bar).
    private static func isOnScreen(_ frame: CGRect) -> Bool {
        NSScreen.screens.contains { screen in
            let bounds = CGDisplayBounds(screen.displayID)
            return frame.minX >= bounds.minX - 1
                && frame.maxX <= bounds.maxX + 1
                && frame.minY >= bounds.minY - 1
                && frame.minY < bounds.minY + 40
        }
    }

    /// Whether `item` sits directly left of `divider`, with no icon between.
    private static func isDirectlyLeft(of divider: CGRect, _ item: CGRect) -> Bool {
        let gap = divider.minX - item.maxX
        return gap >= -1 && gap < 24
    }
}

private extension ControlItem {
    /// Storage for menu items that toggle a menu bar section.
    ///
    /// When one of these menu items is created, its section is stored here.
    /// When its action is invoked, the section is retrieved from storage.
    static let sectionStorage = ObjectStorage<MenuBarSection>()
}

// MARK: - Logger
private extension Logger {
    /// The logger to use for control items.
    static let controlItem = Logger(category: "ControlItem")
}
