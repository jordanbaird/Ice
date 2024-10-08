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

    let name: Name

    let controlItem: ControlItem

    private var rehideTimer: Timer?

    private var rehideMonitor: UniversalEventMonitor?

    private var useIceBar: Bool {
        appState?.settingsManager.generalSettingsManager.useIceBar ?? false
    }

    private var iceBarPanel: IceBarPanel? {
        appState?.menuBarManager.iceBarPanel
    }

    private var screenForIceBar: NSScreen? {
        guard let appState else {
            return nil
        }
        if appState.isActiveSpaceFullscreen {
            return NSScreen.screenWithMouse ?? NSScreen.main
        } else {
            return NSScreen.main
        }
    }

    private(set) weak var appState: AppState? {
        didSet {
            guard let appState else {
                return
            }
            controlItem.assignAppState(appState)
        }
    }

    weak var menuBarManager: MenuBarManager? {
        appState?.menuBarManager
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

    /// Creates a section with the given name and control item.
    init(name: Name, controlItem: ControlItem) {
        self.name = name
        self.controlItem = controlItem
    }

    /// Creates a section with the given name.
    convenience init(name: Name) {
        let identifier: ControlItem.Identifier = switch name {
        case .visible: .iceIcon
        case .hidden: .hidden
        case .alwaysHidden: .alwaysHidden
        }
        self.init(name: name, controlItem: ControlItem(identifier: identifier))
    }

    /// Assigns the section's app state.
    func assignAppState(_ appState: AppState) {
        guard self.appState == nil else {
            Logger.menuBarSection.warning("Multiple attempts made to assign app state")
            return
        }
        self.appState = appState
    }

    /// Shows the section.
    func show() {
        guard
            let menuBarManager,
            isHidden
        else {
            return
        }
        guard controlItem.isAddedToMenuBar else {
            // The section is disabled.
            return
        }
        switch name {
        case .visible where useIceBar, .hidden where useIceBar:
            Task {
                if let screenForIceBar {
                    await iceBarPanel?.show(section: .hidden, on: screenForIceBar)
                }
                for section in menuBarManager.sections {
                    section.controlItem.state = .hideItems
                }
            }
        case .alwaysHidden where useIceBar:
            Task {
                if let screenForIceBar {
                    await iceBarPanel?.show(section: .alwaysHidden, on: screenForIceBar)
                }
                for section in menuBarManager.sections {
                    section.controlItem.state = .hideItems
                }
            }
        case .visible:
            iceBarPanel?.close()
            guard let hiddenSection = menuBarManager.section(withName: .hidden) else {
                return
            }
            controlItem.state = .showItems
            hiddenSection.controlItem.state = .showItems
        case .hidden:
            iceBarPanel?.close()
            guard let visibleSection = menuBarManager.section(withName: .visible) else {
                return
            }
            controlItem.state = .showItems
            visibleSection.controlItem.state = .showItems
        case .alwaysHidden:
            iceBarPanel?.close()
            guard
                let hiddenSection = menuBarManager.section(withName: .hidden),
                let visibleSection = menuBarManager.section(withName: .visible)
            else {
                return
            }
            controlItem.state = .showItems
            hiddenSection.controlItem.state = .showItems
            visibleSection.controlItem.state = .showItems
        }
        startRehideChecks()
    }

    /// Hides the section.
    func hide() {
        guard
            let appState,
            let menuBarManager,
            !isHidden
        else {
            return
        }
        iceBarPanel?.close()
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
        appState.allowShowOnHover()
        stopRehideChecks()
    }

    /// Toggles the visibility of the section.
    func toggle() {
        if isHidden {
            show()
        } else {
            hide()
        }
    }

    private func startRehideChecks() {
        rehideTimer?.invalidate()
        rehideMonitor?.stop()

        guard
            let appState = menuBarManager?.appState,
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
