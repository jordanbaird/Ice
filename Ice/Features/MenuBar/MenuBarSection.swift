//
//  MenuBarSection.swift
//  Ice
//

import Combine
import Foundation
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

    /// Creates a menu bar section with the given name, control item
    /// autosave name, control item position, and control item hiding
    /// state.
    convenience init(
        name: Name,
        autosaveName: String,
        position: CGFloat? = nil,
        state: ControlItem.HidingState? = nil
    ) {
        self.init(
            name: name,
            controlItem: ControlItem(
                autosaveName: autosaveName,
                position: position,
                state: state
            ),
            hotkey: nil
        )
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
            self?.toggle()
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
        case .visible, .hidden:
            guard
                let section1 = menuBarManager.section(withName: .visible),
                let section2 = menuBarManager.section(withName: .hidden)
            else {
                return
            }
            section1.controlItem.state = .showItems
            section2.controlItem.state = .showItems
        case .alwaysHidden:
            guard
                let section1 = menuBarManager.section(withName: .hidden),
                let section2 = menuBarManager.section(withName: .alwaysHidden)
            else {
                return
            }
            section1.show() // uses other branch
            section2.controlItem.state = .showItems
        }
    }

    /// Hides the status items in the section.
    func hide() {
        guard let menuBarManager else {
            return
        }
        switch name {
        case .visible, .hidden:
            guard
                let section1 = menuBarManager.section(withName: .visible),
                let section2 = menuBarManager.section(withName: .hidden),
                let section3 = menuBarManager.section(withName: .alwaysHidden)
            else {
                return
            }
            section1.controlItem.state = .hideItems
            section2.controlItem.state = .hideItems
            section3.hide() // uses other branch
        case .alwaysHidden:
            guard let section = menuBarManager.section(withName: .alwaysHidden) else {
                return
            }
            section.controlItem.state = .hideItems
        }
    }

    /// Toggles the visibility of the status items in the section.
    func toggle() {
        switch controlItem.state {
        case .hideItems: show()
        case .showItems: hide()
        }
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
