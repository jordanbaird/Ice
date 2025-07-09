//
//  MenuBarItemTag.swift
//  Ice
//

import CoreGraphics

// MARK: - MenuBarItemTag

/// An identifier for a menu bar item.
struct MenuBarItemTag: Hashable, CustomStringConvertible {
    /// The namespace of the item identified by this tag.
    let namespace: Namespace

    /// The title of the item identified by this tag.
    let title: String

    /// A Boolean value that indicates whether the item identified
    /// by this tag can be moved.
    var isMovable: Bool {
        !MenuBarItemTag.immovableItems.contains(self)
    }

    /// A Boolean value that indicates whether the item identified
    /// by this tag can be hidden.
    var canBeHidden: Bool {
        !MenuBarItemTag.nonHideableItems.contains(self)
    }

    /// A Boolean value that indicates whether the item identified
    /// by this tag is a control item owned by Ice.
    var isControlItem: Bool {
        MenuBarItemTag.controlItems.contains(self)
    }

    /// A string representation of the tag.
    var stringValue: String {
        var result = namespace.rawValue
        if !title.isEmpty {
            result.append(":\(title)")
        }
        return result
    }

    /// A textual representation of the tag.
    var description: String {
        stringValue
    }

    /// Creates a tag with the given namespace and title.
    init(namespace: Namespace, title: String) {
        self.namespace = namespace
        self.title = title
    }

    /// Creates a tag for the control item with the given identifier.
    private init(controlItem identifier: ControlItem.Identifier) {
        self.init(namespace: .ice, title: identifier.rawValue)
    }
}

// MARK: MenuBarItemTag Constants

extension MenuBarItemTag {

    // MARK: Special Item Lists

    /// An array of tags for items whose movement is prevented by macOS.
    static let immovableItems: [MenuBarItemTag] = {
        var items = [clock, controlCenter]
        if #unavailable(macOS 26.0) {
            items.append(siri)
        }
        return items
    }()

    // TODO: MusicRecognition became hideable in what macOS version?
    //
    // At some point, it became possible to hide the "MusicRecognition" item.
    // We need to determine which version of macOS first had this change, and
    // and conditionally exclude the item from this list.
    //
    // We're using macOS 15.3.2 for now, but it could be earlier.
    //
    /// An array of tags for items that can be moved, but cannot be hidden.
    static let nonHideableItems: [MenuBarItemTag] = {
        var items = [audioVideoModule, faceTime, screenCaptureUI]
        if #unavailable(macOS 15.3.2) {
            items.append(musicRecognition)
        }
        return items
    }()

    /// An array of tags for items representing Ice's control items.
    static let controlItems = ControlItem.Identifier.allCases.map { $0.tag }

    // MARK: Control Items

    /// A tag for the control item for the visible section.
    static let visibleControlItem = MenuBarItemTag(controlItem: .visible)

    /// A tag for the control item for the hidden section.
    static let hiddenControlItem = MenuBarItemTag(controlItem: .hidden)

    /// A tag for the control item for the always-hidden section.
    static let alwaysHiddenControlItem = MenuBarItemTag(controlItem: .alwaysHidden)

    // MARK: Other System Items

    /// A tag for the "Clock" item.
    static let clock = MenuBarItemTag(namespace: .controlCenter, title: "Clock")

    /// A tag for the "Siri" item.
    static let siri: MenuBarItemTag = {
        if #available(macOS 26.0, *) {
            MenuBarItemTag(namespace: .controlCenter, title: "Siri")
        } else {
            MenuBarItemTag(namespace: .systemUIServer, title: "Siri")
        }
    }()

    /// A tag for the "Control Center" item.
    static let controlCenter: MenuBarItemTag = {
        if #available(macOS 26.0, *) {
            MenuBarItemTag(namespace: .controlCenter, title: "BentoBox-0")
        } else {
            MenuBarItemTag(namespace: .controlCenter, title: "BentoBox")
        }
    }()

    /// A tag for the item that appears in the menu bar while the screen
    /// or system audio is being recorded.
    static let audioVideoModule = MenuBarItemTag(namespace: .controlCenter, title: "AudioVideoModule")

    /// A tag for the "FaceTime" item.
    static let faceTime = MenuBarItemTag(namespace: .controlCenter, title: "FaceTime")

    /// A tag for the "MusicRecognition" (a.k.a. "Shazam") item.
    static let musicRecognition = MenuBarItemTag(namespace: .controlCenter, title: "MusicRecognition")

    // TODO: How do we reference this item in macOS 26?
    /// A tag for the "stop recording" item that appears in the menu bar
    /// during screen recordings started by the macOS "Screenshot" tool.
    static let screenCaptureUI = MenuBarItemTag(namespace: .screenCaptureUI, title: "Item-0")
}

// MARK: MenuBarItemTag: Codable
extension MenuBarItemTag: Codable {
    init(from decoder: any Decoder) throws {
        let container = try decoder.singleValueContainer()
        let string = try container.decode(String.self)
        let components = string.components(separatedBy: ":")
        let count = components.count
        if count > 2 {
            self.namespace = Namespace(components[0])
            self.title = components[1...].joined(separator: ":")
        } else if count == 2 {
            self.namespace = Namespace(components[0])
            self.title = components[1]
        } else if count == 1 {
            self.namespace = Namespace(components[0])
            self.title = ""
        } else {
            throw DecodingError.dataCorrupted(
                DecodingError.Context(
                    codingPath: container.codingPath,
                    debugDescription: "Missing namespace component"
                )
            )
        }
    }

    func encode(to encoder: any Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(stringValue)
    }
}

// MARK: - MenuBarItemTag.Namespace

extension MenuBarItemTag {
    /// A type that represents a menu bar item namespace.
    struct Namespace: Codable, Hashable, RawRepresentable, CustomStringConvertible {
        /// Private representation of a namespace.
        private enum Kind {
            case null
            case rawValue(String)
        }

        /// The private representation of the namespace.
        private let kind: Kind

        /// The namespace's raw value.
        var rawValue: String {
            switch kind {
            case .null: "<null>"
            case .rawValue(let rawValue): rawValue
            }
        }

        /// A textual representation of the namespace.
        var description: String {
            rawValue
        }

        /// An Optional representation of the namespace that converts
        /// the ``null`` namespace to `nil`.
        var optional: Namespace? {
            switch kind {
            case .null: nil
            case .rawValue: self
            }
        }

        /// Creates a namespace with the given private representation.
        private init(kind: Kind) {
            self.kind = kind
        }

        /// Creates a namespace with the given raw value.
        ///
        /// - Parameter rawValue: The raw value of the namespace.
        init(rawValue: String) {
            self.init(kind: .rawValue(rawValue))
        }

        /// Creates a namespace with the given raw value.
        ///
        /// - Parameter rawValue: The raw value of the namespace.
        init(_ rawValue: String) {
            self.init(rawValue: rawValue)
        }

        /// Creates a namespace with the given optional value.
        ///
        /// If the provided value is `nil`, the namespace is initialized
        /// to the ``null`` namespace.
        ///
        /// - Parameter value: An optional value for the namespace.
        init(_ value: String?) {
            self = value.map { Namespace($0) } ?? .null
        }
    }
}

// MARK: MenuBarItemTag.Namespace Constants
extension MenuBarItemTag.Namespace {
    /// The namespace for menu bar items owned by Ice.
    static let ice = Self(Constants.bundleIdentifier)

    /// The namespace for menu bar items owned by "Control Center".
    static let controlCenter = Self("com.apple.controlcenter")

    /// The namespace for menu bar items owned by "System UI Server".
    static let systemUIServer = Self("com.apple.systemuiserver")

    /// The namespace for the "stop recording" menu bar item that appears
    /// during screen recordings started by the macOS "Screenshot" tool.
    static let screenCaptureUI = Self("com.apple.screencaptureui")

    /// The namespace for the "Passwords" menu bar item.
    static let passwords = Self("com.apple.Passwords.MenuBarExtra")

    /// The namespace for the "Weather" menu bar item.
    static let weather = Self("com.apple.weather.menu")

    /// The null namespace.
    static let null = Self(kind: .null)
}
