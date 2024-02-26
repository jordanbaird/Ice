//
//  MenuBarSection.swift
//  Ice
//

import Cocoa
import Combine
import OSLog

/// A representation of a section in a menu bar.
final class MenuBarSection: ObservableObject {
    /// User-visible name that describes a menu bar section.
    enum Name: String, Codable, Hashable {
        case visible = "Visible"
        case hidden = "Hidden"
        case alwaysHidden = "Always Hidden"
    }

    /// User-visible name that describes the section.
    @Published var name: Name

    /// A Boolean value that indicates whether the section is enabled.
    @Published var isEnabled: Bool

    /// The control item that manages the visibility of the section.
    @Published var controlItem: ControlItem {
        didSet {
            controlItem.updateStatusItem(with: controlItem.state)
            configureCancellables()
        }
    }

    /// The hotkey associated with the section.
    @Published var hotkey: Hotkey? {
        didSet {
            if listener != nil {
                enableHotkey()
            }
            menuBarManager?.needsSave = true
        }
    }

    private var listener: Hotkey.Listener?

    private var rehideTimer: Timer?

    private var rehideMonitor: UniversalEventMonitor?

    private var cancellables = Set<AnyCancellable>()

    /// The menu bar manager associated with the section.
    weak var menuBarManager: MenuBarManager? {
        didSet {
            controlItem.menuBarManager = menuBarManager
        }
    }

    /// A Boolean value that indicates whether the section is hidden.
    var isHidden: Bool {
        switch controlItem.state {
        case .hideItems: true
        case .showItems: false
        }
    }

    /// A Boolean value that indicates whether the section's hotkey is
    /// enabled.
    var hotkeyIsEnabled: Bool {
        listener != nil
    }

    /// Creates a menu bar section with the given name, control item,
    /// hotkey, and unique identifier.
    init(name: Name, controlItem: ControlItem, hotkey: Hotkey? = nil) {
        self.name = name
        self.controlItem = controlItem
        self.hotkey = hotkey
        self.isEnabled = controlItem.isVisible
        enableHotkey()
        configureCancellables()
    }

    /// Creates a menu bar section with the given name.
    convenience init(name: Name) {
        let controlItem = switch name {
        case .visible:
            ControlItem(autosaveName: "Item-1", position: 0, state: nil)
        case .hidden:
            ControlItem(autosaveName: "Item-2", position: 1, state: nil)
        case .alwaysHidden:
            ControlItem(autosaveName: "Item-3", position: nil, state: .hideItems)
        }
        self.init(name: name, controlItem: controlItem, hotkey: nil)
    }

    private func configureCancellables() {
        var c = Set<AnyCancellable>()

        // propagate changes from the section's control item
        controlItem.objectWillChange
            .sink { [weak self] in
                self?.objectWillChange.send()
            }
            .store(in: &c)

        controlItem.$isVisible
            .removeDuplicates()
            .sink { [weak self] isVisible in
                guard
                    let self,
                    isEnabled != isVisible
                else {
                    return
                }
                isEnabled = isVisible
            }
            .store(in: &c)

        $isEnabled
            .removeDuplicates()
            .sink { [weak self] isEnabled in
                guard
                    let self,
                    controlItem.isVisible != isEnabled
                else {
                    return
                }
                controlItem.isVisible = isEnabled
                if isEnabled {
                    enableHotkey()
                } else {
                    disableHotkey()
                }
            }
            .store(in: &c)

        cancellables = c
    }

    /// Enables the hotkey associated with the section.
    func enableHotkey() {
        listener = hotkey?.onKeyDown { [weak self] in
            guard let self else {
                return
            }
            toggle()
            // prevent the section from automatically rehiding
            // after mouse movement
            menuBarManager?.showOnHoverPreventedByUserInteraction = !isHidden
        }
    }

    /// Disables the hotkey associated with the section.
    func disableHotkey() {
        listener?.invalidate()
        listener = nil
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
        startRehideMonitor()
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
        menuBarManager.showOnHoverPreventedByUserInteraction = false
        rehideTimer?.invalidate()
        rehideMonitor?.stop()
        rehideTimer = nil
        rehideMonitor = nil
    }

    /// Toggles the visibility of the status items in the section.
    func toggle() {
        switch controlItem.state {
        case .hideItems: show()
        case .showItems: hide()
        }
    }

    private func startRehideMonitor() {
        rehideTimer?.invalidate()
        rehideMonitor?.stop()

        guard
            let menuBarManager,
            menuBarManager.autoRehide,
            case .timed = menuBarManager.rehideStrategy
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
                        withTimeInterval: menuBarManager.rehideInterval,
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
                            startRehideMonitor()
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
}

// MARK: MenuBarSection: Codable
extension MenuBarSection: Codable {
    private enum CodingKeys: String, CodingKey {
        case name
        case controlItem
        case hotkey
    }

    convenience init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        try self.init(
            name: container.decode(Name.self, forKey: .name),
            controlItem: container.decode(ControlItem.self, forKey: .controlItem),
            hotkey: container.decodeIfPresent(Hotkey.self, forKey: .hotkey)
        )
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(name, forKey: .name)
        try container.encode(controlItem, forKey: .controlItem)
        try container.encodeIfPresent(hotkey, forKey: .hotkey)
    }
}

// MARK: MenuBarSection: Equatable
extension MenuBarSection: Equatable {
    static func == (lhs: MenuBarSection, rhs: MenuBarSection) -> Bool {
        lhs.name == rhs.name &&
        lhs.controlItem == rhs.controlItem &&
        lhs.hotkey == rhs.hotkey
    }
}

// MARK: MenuBarSection: Hashable
extension MenuBarSection: Hashable {
    func hash(into hasher: inout Hasher) {
        hasher.combine(name)
        hasher.combine(controlItem)
        hasher.combine(hotkey)
    }
}

// MARK: MenuBarSection: BindingExposable
extension MenuBarSection: BindingExposable { }
