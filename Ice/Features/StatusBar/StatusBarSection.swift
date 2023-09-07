//
//  StatusBarSection.swift
//  Ice
//

import Combine
import Foundation

/// A representation of a section in a status bar.
final class StatusBarSection: ObservableObject {

    // MARK: Name

    /// User-visible name that describes a status bar section.
    struct Name: Codable, ExpressibleByStringInterpolation, Hashable, RawRepresentable {
        var rawValue: String

        init(rawValue: String) {
            self.rawValue = rawValue
        }

        init(stringLiteral value: String) {
            self.init(rawValue: value)
        }

        /// The name for the always-visible section.
        static let alwaysVisible = Name(rawValue: "Always Visible")

        /// The name for the hidden section.
        static let hidden = Name(rawValue: "Hidden")

        /// The name for the always-hidden section.
        static let alwaysHidden = Name(rawValue: "Always Hidden")
    }

    /// Observers that manage the key state of the section.
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

    /// The section's persistent unique identifier.
    let uuid: UUID

    /// The status bar associated with the section.
    weak var statusBar: StatusBar? {
        didSet {
            controlItem.statusBar = statusBar
        }
    }

    /// A Boolean value that indicates whether the section is enabled.
    var isEnabled: Bool {
        controlItem.isVisible
    }

    /// A Boolean value that indicates whether the section's hotkey is
    /// enabled.
    var hotkeyIsEnabled: Bool {
        listener != nil
    }

    /// Creates a status bar section with the given name, control item,
    /// hotkey, and unique identifier.
    init(name: Name, controlItem: ControlItem, hotkey: Hotkey? = nil, uuid: UUID = UUID()) {
        self.name = name
        self.controlItem = controlItem
        self.hotkey = hotkey
        self.uuid = uuid
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
            guard let self else {
                return
            }
            statusBar?.toggle(section: self)
        }
    }

    /// Disables the hotkey associated with the section.
    func disableHotkey() {
        listener?.invalidate()
        listener = nil
    }
}

// MARK: StatusBarSection: Codable
extension StatusBarSection: Codable {
    private enum CodingKeys: String, CodingKey {
        case name
        case controlItem
        case hotkey
        case uuid
    }

    convenience init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        try self.init(
            name: container.decode(Name.self, forKey: .name),
            controlItem: container.decode(ControlItem.self, forKey: .controlItem),
            hotkey: container.decodeIfPresent(Hotkey.self, forKey: .hotkey),
            uuid: container.decode(UUID.self, forKey: .uuid)
        )
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(name, forKey: .name)
        try container.encode(controlItem, forKey: .controlItem)
        try container.encodeIfPresent(hotkey, forKey: .hotkey)
        try container.encode(uuid, forKey: .uuid)
    }
}

// MARK: StatusBarSection: Equatable
extension StatusBarSection: Equatable {
    static func == (lhs: StatusBarSection, rhs: StatusBarSection) -> Bool {
        lhs.name == rhs.name &&
        lhs.controlItem == rhs.controlItem &&
        lhs.hotkey == rhs.hotkey &&
        lhs.uuid == rhs.uuid
    }
}

// MARK: StatusBarSection: Hashable
extension StatusBarSection: Hashable {
    func hash(into hasher: inout Hasher) {
        hasher.combine(name)
        hasher.combine(controlItem)
        hasher.combine(hotkey)
        hasher.combine(uuid)
    }
}
