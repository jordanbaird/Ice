//
//  MenuBarSection.swift
//  Ice
//

import Cocoa
import Combine
import OSLog

/// A representation of a section in a menu bar.
final class MenuBarSection: ObservableObject {
    @Published private(set) var isHidden: Bool

    let name: Name

    let controlItem: ControlItem

    private var rehideTimer: Timer?

    private var rehideMonitor: UniversalEventMonitor?

    private var cancellables = Set<AnyCancellable>()

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

    init(name: Name, controlItem: ControlItem) {
        self.name = name
        self.controlItem = controlItem
        self.isHidden = controlItem.state == .hideItems
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

        controlItem.$state
            .sink { [weak self] state in
                self?.isHidden = state == .hideItems
            }
            .store(in: &c)

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
        guard let menuBarManager else {
            return
        }
        switch name {
        case .visible:
            guard let hiddenSection = menuBarManager.section(withName: .hidden) else {
                return
            }
            controlItem.state = .showItems
            hiddenSection.controlItem.state = .showItems
        case .hidden:
            guard let visibleSection = menuBarManager.section(withName: .visible) else {
                return
            }
            controlItem.state = .showItems
            visibleSection.controlItem.state = .showItems
        case .alwaysHidden:
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
        guard let menuBarManager else {
            return
        }
        switch name {
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
        appState?.showOnHoverIsPreventedByUserInteraction = false
        stopRehideChecks()
    }

    /// Toggles the visibility of the status items in the section.
    func toggle() {
        switch controlItem.state {
        case .hideItems: show()
        case .showItems: hide()
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
                            hide()
                        } else {
                            startRehideChecks()
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
    enum Name {
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
    }
}

// MARK: - Logger
private extension Logger {
    static let menuBarSection = Logger(category: "MenuBarSection")
}
