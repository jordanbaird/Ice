//
//  MenuBarItemInfo.swift
//  Ice
//

/// A simplified version of a menu bar item.
struct MenuBarItemInfo: Hashable, CustomStringConvertible {
    /// The namespace of the item.
    let namespace: Namespace

    /// The title of the item.
    let title: String

    /// A Boolean value that indicates whether the item is within the
    /// "Special" namespace.
    var isSpecial: Bool {
        namespace == .special
    }

    var description: String {
        namespace.rawValue + ":" + title
    }

    /// Creates a simplified item with the given namespace and title.
    init(namespace: Namespace, title: String) {
        self.namespace = namespace
        self.title = title
    }
}

// MARK: MenuBarItemInfo Constants
extension MenuBarItemInfo {
    /// An array of items whose movement is prevented by macOS.
    static let immovableItems = [clock, siri, controlCenter]

    /// An array of items that can be moved, but cannot be hidden.
    static let nonHideableItems = [audioVideoModule, faceTime, musicRecognition]

    /// Information for an item that represents the Ice icon, a.k.a. the
    /// control item for the visible section.
    static let iceIcon = MenuBarItemInfo(
        namespace: .ice,
        title: ControlItem.Identifier.iceIcon.rawValue
    )

    /// Information for an item that represents the control item for the
    /// hidden section.
    static let hiddenControlItem = MenuBarItemInfo(
        namespace: .ice,
        title: ControlItem.Identifier.hidden.rawValue
    )

    /// Information for an item that represents the control item for the
    /// always-hidden section.
    static let alwaysHiddenControlItem = MenuBarItemInfo(
        namespace: .ice,
        title: ControlItem.Identifier.alwaysHidden.rawValue
    )

    /// Information for the "Clock" item.
    static let clock = MenuBarItemInfo(
        namespace: .controlCenter,
        title: "Clock"
    )

    /// Information for the "Siri" item.
    static let siri = MenuBarItemInfo(
        namespace: .systemUIServer,
        title: "Siri"
    )

    /// Information for the "BentoBox" (a.k.a. "Control Center") item.
    static let controlCenter = MenuBarItemInfo(
        namespace: .controlCenter,
        title: "BentoBox"
    )

    /// Information for the item that appears in the menu bar while the
    /// screen or system audio is being recorded.
    static let audioVideoModule = MenuBarItemInfo(
        namespace: .controlCenter,
        title: "AudioVideoModule"
    )

    /// Information for the "FaceTime" item.
    static let faceTime = MenuBarItemInfo(
        namespace: .controlCenter,
        title: "FaceTime"
    )

    /// Information for the "MusicRecognition" (a.k.a. "Shazam") item.
    static let musicRecognition = MenuBarItemInfo(
        namespace: .controlCenter,
        title: "MusicRecognition"
    )

    /// Information for a special item that indicates the location where
    /// new menu bar items should appear.
    static let newItems = MenuBarItemInfo(
        namespace: .special,
        title: "NewItems"
    )
}

// MARK: MenuBarItemInfo: Codable
extension MenuBarItemInfo: Codable {
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
        try container.encode([namespace.rawValue, title].joined(separator: ":"))
    }
}

// MARK: - MenuBarItemInfo.Namespace

extension MenuBarItemInfo {
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

        /// An Optional representation of the namespace that converts the ``null``
        /// namespace to `nil`.
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
        /// If the provided value is `nil`, the namespace is initialized to the ``null``
        /// namespace.
        ///
        /// - Parameter value: An optional value to initialize the namespace with.
        init(_ value: String?) {
            self = value.map { Namespace($0) } ?? .null
        }
    }
}

// MARK: MenuBarItemInfo.Namespace Constants
extension MenuBarItemInfo.Namespace {
    /// The namespace for menu bar items owned by Ice.
    static let ice = Self(Constants.bundleIdentifier)

    /// The namespace for menu bar items owned by Control Center.
    static let controlCenter = Self("com.apple.controlcenter")

    /// The namespace for menu bar items owned by the System UI Server.
    static let systemUIServer = Self("com.apple.systemuiserver")

    /// The namespace for special items.
    static let special = Self("Special")

    /// The null namespace.
    static let null = Self(kind: .null)
}
