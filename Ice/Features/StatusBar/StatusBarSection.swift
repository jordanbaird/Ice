//
//  StatusBarSection.swift
//  Ice
//

import Combine
import Foundation
import OSLog

/// A representation of a section in a status bar.
final class StatusBarSection: ObservableObject {
    /// User-visible name that describes a status bar section.
    enum Name: String, Codable, Hashable {
        case alwaysVisible = "Always Visible"
        case hidden = "Hidden"
        case alwaysHidden = "Always Hidden"
    }

    private var cancellables = Set<AnyCancellable>()

    /// A value that manages the lifetime of the hotkey's observation.
    private var listener: Hotkey.Listener?

    /// User-visible name that describes the section.
    @Published var name: Name

    /// The control item that manages the visibility of the section.
    @Published var controlItem: ControlItem {
        didSet {
            controlItem.updateStatusItem()
            configureCancellables()
        }
    }

    /// The hotkey associated with the section.
    @Published var hotkey: Hotkey? {
        didSet {
            if listener != nil {
                enableHotkey()
            }
            statusBar?.needsSave = true
        }
    }

    /// The status bar associated with the section.
    weak var statusBar: StatusBar? {
        didSet {
            controlItem.statusBar = statusBar
        }
    }

    /// A Boolean value that indicates whether the section is enabled.
    var isEnabled: Bool {
        get { controlItem.isVisible }
        set { controlItem.isVisible = newValue }
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

    /// Creates a status bar section with the given name, control item,
    /// hotkey, and unique identifier.
    init(name: Name, controlItem: ControlItem, hotkey: Hotkey? = nil) {
        self.name = name
        self.controlItem = controlItem
        self.hotkey = hotkey
        enableHotkey()
        configureCancellables()
    }

    /// Set up a series of cancellables to respond to important changes
    /// in the section's state.
    private func configureCancellables() {
        var c = Set<AnyCancellable>()

        // propagate changes from the section's control item
        c.insert(controlItem.objectWillChange.sink { [weak self] in
            self?.objectWillChange.send()
        })

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
        guard let statusBar else {
            return
        }
        switch name {
        case .alwaysVisible, .hidden:
            guard
                let section1 = statusBar.section(withName: .alwaysVisible),
                let section2 = statusBar.section(withName: .hidden)
            else {
                return
            }
            section1.controlItem.state = .showItems
            section2.controlItem.state = .showItems
        case .alwaysHidden:
            guard
                let section1 = statusBar.section(withName: .hidden),
                let section2 = statusBar.section(withName: .alwaysHidden)
            else {
                return
            }
            section1.show() // uses other branch
            section2.controlItem.state = .showItems
        }
    }

    /// Hides the status items in the section.
    func hide() {
        guard let statusBar else {
            return
        }
        switch name {
        case .alwaysVisible, .hidden:
            guard
                let section1 = statusBar.section(withName: .alwaysVisible),
                let section2 = statusBar.section(withName: .hidden),
                let section3 = statusBar.section(withName: .alwaysHidden)
            else {
                return
            }
            section1.controlItem.state = .hideItems(isExpanded: false)
            section2.controlItem.state = .hideItems(isExpanded: true)
            section3.hide() // uses other branch
        case .alwaysHidden:
            guard let section = statusBar.section(withName: .alwaysHidden) else {
                return
            }
            section.controlItem.state = .hideItems(isExpanded: true)
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

// MARK: StatusBarSection: Codable
extension StatusBarSection: Codable {
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

// MARK: StatusBarSection: Equatable
extension StatusBarSection: Equatable {
    static func == (lhs: StatusBarSection, rhs: StatusBarSection) -> Bool {
        lhs.name == rhs.name &&
        lhs.controlItem == rhs.controlItem &&
        lhs.hotkey == rhs.hotkey
    }
}

// MARK: StatusBarSection: Hashable
extension StatusBarSection: Hashable {
    func hash(into hasher: inout Hasher) {
        hasher.combine(name)
        hasher.combine(controlItem)
        hasher.combine(hotkey)
    }
}

// MARK: StatusBarSection: BindingExposable
extension StatusBarSection: BindingExposable { }
