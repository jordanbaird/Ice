//
//  MenuBarSection.swift
//  Ice
//

import Cocoa
import Combine

/// A representation of a section in a menu bar.
@MainActor
final class MenuBarSection {
    /// The name of a menu bar section.
    enum Name: CaseIterable {
        case visible
        case hidden
        case alwaysHidden

        /// A string to show in the interface.
        var displayString: String {
            switch self {
            case .visible: "Visible"
            case .hidden: "Hidden"
            case .alwaysHidden: "Always-Hidden"
            }
        }

        /// A string to use for logging purposes.
        var logString: String {
            switch self {
            case .visible: "visible section"
            case .hidden: "hidden section"
            case .alwaysHidden: "always-hidden section"
            }
        }
    }

    /// The name of the section.
    let name: Name

    /// The control item that manages the section.
    let controlItem: ControlItem

    /// Storage for internal observers.
    private var cancellables = Set<AnyCancellable>()

    /// The shared app state.
    private weak var appState: AppState?

    /// Earliest date at which a new toggle may start.
    ///
    /// Spam-clicking the divider (or mashing the hotkey) reverses the native
    /// icon slide mid-flight, so the icons never rest and the pill chases a
    /// moving target forever. Toggles inside the cooldown are dropped.
    private var nextToggleDate = Date.distantPast

    /// Minimum gap between two toggles, so one slide animation always
    /// finishes before the next one starts.
    private static let toggleCooldown: TimeInterval = 0.25

    /// A timer that manages rehiding the section.
    private var rehideTimer: Timer?

    /// Whether state changes currently represent a durable user choice.
    private var persistsStateChanges = true

    /// Changes even for transient updates, so temporary reveals cannot undo a newer choice.
    private(set) var stateRevision = 0

    /// An event monitor that handles starting the rehide timer when the mouse
    /// is outside of the menu bar.
    private var rehideMonitor: UniversalEventMonitor?

    /// A Boolean value that indicates whether the Ice Bar should be used.
    private var useIceBar: Bool {
        appState?.settingsManager.generalSettingsManager.useIceBar ?? false
    }

    /// A weak reference to the menu bar manager's Ice Bar panel.
    private weak var iceBarPanel: IceBarPanel? {
        appState?.menuBarManager.iceBarPanel
    }

    /// The best screen to show the Ice Bar on.
    private weak var screenForIceBar: NSScreen? {
        guard let appState else {
            return nil
        }
        if appState.isActiveSpaceFullscreen {
            return NSScreen.screenWithMouse ?? NSScreen.main
        } else {
            return NSScreen.main
        }
    }

    /// A Boolean value that indicates whether the section is hidden.
    var isHidden: Bool {
        if useIceBar {
            if controlItem.state == .showItems {
                return false
            }
            switch name {
            case .visible, .hidden:
                return iceBarPanel?.currentSection != .hidden
            case .alwaysHidden:
                return iceBarPanel?.currentSection != .alwaysHidden
            }
        }
        switch name {
        case .visible, .hidden:
            if iceBarPanel?.currentSection == .hidden {
                return false
            }
            return controlItem.state == .hideItems
        case .alwaysHidden:
            if iceBarPanel?.currentSection == .alwaysHidden {
                return false
            }
            return controlItem.state == .hideItems
        }
    }

    /// A Boolean value that indicates whether the section is enabled.
    var isEnabled: Bool {
        if case .visible = name {
            // The visible section should always be enabled.
            return true
        }
        return controlItem.isAddedToMenuBar
    }

    /// Creates a section with the given name, control item, and app state.
    init(name: Name, controlItem: ControlItem, appState: AppState) {
        self.name = name
        self.controlItem = controlItem
        self.appState = appState
        // Restore the visibility the user last chose; a fresh install
        // defaults to hidden, matching the previous launch behavior.
        // Exception: on macOS 27 the pre-reveal population (no 0.11.27
        // migration flag yet) starts shown, so icons trapped out of sight
        // by the old hidden default come back (issue #17). Decided here at
        // init instead of in the async migration so no launch race can
        // strand the sections hidden; the migration persists the outcome.
        controlItem.state = Self.initialState(for: shownDefaultsKey)
        controlItem.$state
            .sink { [weak self] state in
                guard let self else {
                    return
                }
                stateRevision += 1
                guard persistsStateChanges else {
                    return
                }
                Defaults.set(state == .showItems, forKey: shownDefaultsKey)
                // The Ice icon mirrors the always-hidden section; repaint
                // its arrow when that section changes.
                if
                    name == .alwaysHidden,
                    let visibleSection = self.appState?.menuBarManager.section(withName: .visible)
                {
                    visibleSection.controlItem.updateStatusItem(with: visibleSection.controlItem.state)
                }
            }
            .store(in: &cancellables)
    }

    /// Creates a section with the given name and app state.
    convenience init(name: Name, appState: AppState) {
        let controlItem = switch name {
        case .visible:
            ControlItem(identifier: .iceIcon, appState: appState)
        case .hidden:
            ControlItem(identifier: .hidden, appState: appState)
        case .alwaysHidden:
            ControlItem(identifier: .alwaysHidden, appState: appState)
        }
        self.init(name: name, controlItem: controlItem, appState: appState)
    }

    /// The UserDefaults key that stores whether the section is shown.
    private var shownDefaultsKey: Defaults.Key {
        switch name {
        case .visible: .showVisibleSection
        case .hidden: .showHiddenSection
        case .alwaysHidden: .showAlwaysHiddenSection
        }
    }

    /// The hiding state a section starts in for the given persisted key.
    ///
    /// Before the 0.11.27 migration has run on macOS 27, starts shown: the
    /// old hidden default (or a stored hidden choice from when dividers
    /// could be placed) can otherwise trap icons out of sight with no
    /// working drag to pull them back. Afterwards the stored choice wins.
    private static func initialState(for key: Defaults.Key) -> ControlItem.HidingState {
        if #available(macOS 27, *), !Defaults.bool(forKey: .hasMigrated0_11_27) {
            return .showItems
        }
        return Defaults.bool(forKey: key) ? .showItems : .hideItems
    }

    /// Shows the section.
    func show() {
        guard
            let appState,
            isHidden
        else {
            return
        }
        guard controlItem.isAddedToMenuBar else {
            // The section is disabled.
            // TODO: Can we use isEnabled for this check?
            return
        }
        switch name {
        case .visible where useIceBar, .hidden where useIceBar:
            // The Ice Bar shows items WITHOUT expanding the menu bar: the spacer stays put.
            // The bar lists whatever AX sees (dividersMissing → show everything);
            // deeply parked items with no AX node can't be listed — an accepted
            // trade-off per the user's call (menu bar must not jut left).
            Task {
                if let screenForIceBar {
                    await iceBarPanel?.show(section: .hidden, on: screenForIceBar)
                }
            }
        case .alwaysHidden where useIceBar:
            // Same as above: clicking the Ice icon only shows the bar below,
            // the menu bar stays put.
            Task {
                if let screenForIceBar {
                    await iceBarPanel?.show(section: .alwaysHidden, on: screenForIceBar)
                }
            }
        case .visible:
            iceBarPanel?.close()
            guard let hiddenSection = appState.menuBarManager.section(withName: .hidden) else {
                return
            }
            setState(.showItems, persist: true)
            hiddenSection.setState(.showItems, persist: true)
        case .hidden:
            iceBarPanel?.close()
            guard let visibleSection = appState.menuBarManager.section(withName: .visible) else {
                return
            }
            setState(.showItems, persist: true)
            visibleSection.setState(.showItems, persist: true)
        case .alwaysHidden:
            iceBarPanel?.close()
            guard
                let hiddenSection = appState.menuBarManager.section(withName: .hidden),
                let visibleSection = appState.menuBarManager.section(withName: .visible)
            else {
                return
            }
            setState(.showItems, persist: true)
            hiddenSection.setState(.showItems, persist: true)
            visibleSection.setState(.showItems, persist: true)
        }
        startRehideChecks()
    }

    /// Updates this section's state with an explicit persistence intent.
    func setState(_ state: ControlItem.HidingState, persist: Bool) {
        let previousPersistence = persistsStateChanges
        persistsStateChanges = persist
        controlItem.state = state
        persistsStateChanges = previousPersistence
    }

    /// Hides the section.
    ///
    /// - Parameter persistState: Whether the new state should become the
    ///   user's stored choice. Automatic rehide is transient and must not
    ///   replace an explicit reveal from a later launch.
    func hide(persistState: Bool = true) {
        guard
            persistState || iceBarPanel?.isActivatingAXItem != true,
            let appState,
            !isHidden
        else {
            return
        }
        iceBarPanel?.close()
        switch name {
        case _ where useIceBar:
            for section in appState.menuBarManager.sections {
                section.setState(.hideItems, persist: persistState)
            }
        case .visible:
            guard
                let hiddenSection = appState.menuBarManager.section(withName: .hidden),
                let alwaysHiddenSection = appState.menuBarManager.section(withName: .alwaysHidden)
            else {
                return
            }
            setState(.hideItems, persist: persistState)
            hiddenSection.setState(.hideItems, persist: persistState)
            alwaysHiddenSection.setState(.hideItems, persist: persistState)
        case .hidden:
            guard
                let visibleSection = appState.menuBarManager.section(withName: .visible),
                let alwaysHiddenSection = appState.menuBarManager.section(withName: .alwaysHidden)
            else {
                return
            }
            setState(.hideItems, persist: persistState)
            visibleSection.setState(.hideItems, persist: persistState)
            alwaysHiddenSection.setState(.hideItems, persist: persistState)
        case .alwaysHidden:
            setState(.hideItems, persist: persistState)
        }
        appState.allowShowOnHover()
        stopRehideChecks()
    }

    /// Toggles the visibility of the section.
    ///
    /// Drops toggles that arrive inside ``toggleCooldown`` of the previous
    /// one: reversing the slide mid-flight leaves icons and pill permanently
    /// out of sync, so spam clicks wait for the animation to land instead.
    func toggle() {
        guard Date() >= nextToggleDate else {
            return
        }
        nextToggleDate = Date().addingTimeInterval(Self.toggleCooldown)
        if isHidden {
            show()
        } else {
            hide()
        }
    }

    /// Starts running checks to determine when to rehide the section.
    func startRehideChecks() {
        rehideTimer?.invalidate()
        rehideTimer = nil
        rehideMonitor?.stop()

        guard
            let appState,
            appState.settingsManager.generalSettingsManager.autoRehide,
            case .timed = appState.settingsManager.generalSettingsManager.rehideStrategy
        else {
            return
        }

        rehideMonitor = UniversalEventMonitor(mask: .mouseMoved) { [weak self] event in
            guard
                let self,
                let screen = NSScreen.main
            else {
                return event
            }
            if NSEvent.mouseLocation.y < screen.visibleFrame.maxY {
                if rehideTimer == nil {
                    rehideTimer = .scheduledTimer(
                        withTimeInterval: appState.settingsManager.generalSettingsManager.rehideInterval,
                        repeats: false
                    ) { [weak self] _ in
                        guard
                            let self,
                            let screen = NSScreen.main
                        else {
                            return
                        }
                        if NSEvent.mouseLocation.y < screen.visibleFrame.maxY {
                            Task {
                                await self.hide(persistState: false)
                            }
                        } else {
                            Task {
                                await self.startRehideChecks()
                            }
                        }
                    }
                }
            } else {
                rehideTimer?.invalidate()
                rehideTimer = nil
            }
            return event
        }

        rehideMonitor?.start()
    }

    /// Stops running checks to determine when to rehide the section.
    private func stopRehideChecks() {
        rehideTimer?.invalidate()
        rehideMonitor?.stop()
        rehideTimer = nil
        rehideMonitor = nil
    }
}

// MARK: MenuBarSection: BindingExposable
extension MenuBarSection: BindingExposable { }

// MARK: - Logger
private extension Logger {
    static let menuBarSection = Logger(category: "MenuBarSection")
}
