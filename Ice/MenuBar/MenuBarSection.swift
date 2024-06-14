//
//  MenuBarSection.swift
//  Ice
//

import Cocoa
import Combine
import OSLog

/// A representation of a section in a menu bar.
@MainActor
final class MenuBarSection: ObservableObject {
    let name: Name

    let controlItem: ControlItem

    private var rehideTimer: Timer?

    private var rehideMonitor: UniversalEventMonitor?

    private var cancellables = Set<AnyCancellable>()

    private var useIceBar: Bool {
        appState?.settingsManager.generalSettingsManager.useIceBar ?? false
    }

    private var iceBarPanel: IceBarPanel? {
        appState?.menuBarManager.iceBarPanel
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

    init(name: Name, controlItem: ControlItem) {
        self.name = name
        self.controlItem = controlItem
        configureCancellables()
    }

    /// Creates a menu bar section with the given name.
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

    private func configureCancellables() {
        var c = Set<AnyCancellable>()

        // propagate changes from the section's control item
        controlItem.objectWillChange
            .sink { [weak self] in
                self?.objectWillChange.send()
            }
            .store(in: &c)

        cancellables = c
    }

    /// Assigns the section's app state.
    func assignAppState(_ appState: AppState) {
        guard self.appState == nil else {
            Logger.menuBarSection.warning("Multiple attempts made to assign app state")
            return
        }
        self.appState = appState
    }

    /// Shows the status items in the section.
    func show() {
        guard
            let appState,
            let menuBarManager,
            isHidden
        else {
            return
        }
        switch name {
        case .visible where useIceBar, .hidden where useIceBar:
            Task {
                await appState.itemManager.rehideTemporarilyShownItems()
                if let screen = NSScreen.main {
                    iceBarPanel?.show(section: .hidden, on: screen)
                }
                for section in menuBarManager.sections {
                    section.controlItem.state = .hideItems
                }
            }
        case .alwaysHidden where useIceBar:
            Task {
                await appState.itemManager.rehideTemporarilyShownItems()
                if let screen = NSScreen.main {
                    iceBarPanel?.show(section: .alwaysHidden, on: screen)
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

    /// Hides the status items in the section.
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

    /// Toggles the visibility of the status items in the section.
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

// MARK: MenuBarSection.Name
extension MenuBarSection {
    /// The name of a menu bar section.
    enum Name: CaseIterable {
        case visible
        case hidden
        case alwaysHidden

        var deprecatedRawValue: String {
            switch self {
            case .visible: "Visible"
            case .hidden: "Hidden"
            case .alwaysHidden: "Always Hidden"
            }
        }

        var menuString: String {
            switch self {
            case .visible: "Visible"
            case .hidden: "Hidden"
            case .alwaysHidden: "Always-Hidden"
            }
        }

        var logString: String {
            switch self {
            case .visible: "visible"
            case .hidden: "hidden"
            case .alwaysHidden: "always-hidden"
            }
        }
    }
}

// MARK: - Logger
private extension Logger {
    static let menuBarSection = Logger(category: "MenuBarSection")
}
