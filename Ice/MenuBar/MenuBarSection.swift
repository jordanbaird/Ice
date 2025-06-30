//
//  MenuBarSection.swift
//  Ice
//

import Cocoa

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

    /// The shared app state.
    private weak var appState: AppState?

    /// A timer that manages rehiding the section.
    private var rehideTimer: Timer?

    /// An event monitor that handles starting the rehide timer when the mouse
    /// is outside of the menu bar.
    private var rehideMonitor: UniversalEventMonitor?

    /// A Boolean value that indicates whether the Ice Bar should be used.
    private var useIceBar: Bool {
        appState?.settingsManager.generalSettingsManager.useIceBar ?? false
    }

    /// A weak reference to the menu bar manager.
    private weak var menuBarManager: MenuBarManager? {
        appState?.menuBarManager
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
                return menuBarManager?.iceBarPanel.currentSection != .hidden
            case .alwaysHidden:
                return menuBarManager?.iceBarPanel.currentSection != .alwaysHidden
            }
        }
        switch name {
        case .visible, .hidden:
            if menuBarManager?.iceBarPanel.currentSection == .hidden {
                return false
            }
            return controlItem.state == .hideItems
        case .alwaysHidden:
            if menuBarManager?.iceBarPanel.currentSection == .alwaysHidden {
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

    /// Creates a section with the given name and control item.
    init(name: Name, controlItem: ControlItem) {
        self.name = name
        self.controlItem = controlItem
    }

    /// Creates a section with the given name.
    convenience init(name: Name) {
        let controlItem = switch name {
        case .visible:
            ControlItem(identifier: .iceIcon)
        case .hidden:
            ControlItem(identifier: .hidden)
        case .alwaysHidden:
            ControlItem(identifier: .alwaysHidden)
        }
        self.init(name: name, controlItem: controlItem)
    }

    /// Performs the initial setup of the section.
    func performSetup(with appState: AppState) {
        self.appState = appState
        controlItem.performSetup(with: appState)
    }

    /// Shows the section.
    func show() async {
        guard let menuBarManager, isHidden else {
            return
        }

        guard controlItem.isAddedToMenuBar else {
            // The section is disabled.
            // TODO: Can we use isEnabled for this check?
            return
        }

        defer {
            startRehideChecks()
        }

        if useIceBar {
            for section in menuBarManager.sections {
                section.controlItem.state = switch section.name {
                case .visible: .showItems
                default: .hideItems
                }
            }
            if let screen = screenForIceBar {
                switch name {
                case .visible, .hidden:
                    await menuBarManager.iceBarPanel.show(section: .hidden, on: screen)
                case .alwaysHidden:
                    await menuBarManager.iceBarPanel.show(section: .alwaysHidden, on: screen)
                }
            }
        } else {
            // Make sure the Ice bar is closed.
            menuBarManager.iceBarPanel.close()
            var controlItems = [ControlItem]()
            switch name {
            case .visible:
                if let hiddenControlItem = menuBarManager.controlItem(withName: .hidden) {
                    controlItems.append(controlItem)
                    controlItems.append(hiddenControlItem)
                }
            case .hidden:
                if let visibleControlItem = menuBarManager.controlItem(withName: .visible) {
                    controlItems.append(controlItem)
                    controlItems.append(visibleControlItem)
                }
            case .alwaysHidden:
                if
                    let hiddenControlItem = menuBarManager.controlItem(withName: .hidden),
                    let visibleControlItem = menuBarManager.controlItem(withName: .visible)
                {
                    controlItems.append(controlItem)
                    controlItems.append(hiddenControlItem)
                    controlItems.append(visibleControlItem)
                }
            }
            for controlItem in controlItems {
                controlItem.state = .showItems
            }
        }
    }

    /// Hides the section.
    func hide() {
        guard let menuBarManager, !isHidden else {
            return
        }
        // Make sure the Ice bar is always closed.
        menuBarManager.iceBarPanel.close()
        switch name {
        case _ where useIceBar:
            for section in menuBarManager.sections {
                section.controlItem.state = .hideItems
            }
        case .visible:
            guard
                let hiddenSection = menuBarManager.section(withName: .hidden),
                let alwaysHiddenSection = menuBarManager.section(withName: .alwaysHidden)
            else {
                return
            }
            controlItem.state = .hideItems
            hiddenSection.controlItem.state = .hideItems
            alwaysHiddenSection.controlItem.state = .hideItems
        case .hidden:
            guard
                let visibleSection = menuBarManager.section(withName: .visible),
                let alwaysHiddenSection = menuBarManager.section(withName: .alwaysHidden)
            else {
                return
            }
            controlItem.state = .hideItems
            visibleSection.controlItem.state = .hideItems
            alwaysHiddenSection.controlItem.state = .hideItems
        case .alwaysHidden:
            controlItem.state = .hideItems
        }
        menuBarManager.showOnHoverAllowed = true
        stopRehideChecks()
    }

    /// Toggles the visibility of the section.
    func toggle() async {
        if isHidden {
            await show()
        } else {
            hide()
        }
    }

    /// Starts running checks to determine when to rehide the section.
    private func startRehideChecks() {
        rehideTimer?.invalidate()
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
                                await self.hide()
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
