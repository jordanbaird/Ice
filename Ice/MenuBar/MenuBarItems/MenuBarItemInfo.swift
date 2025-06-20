//
//  MenuBarItemInfo.swift
//  Ice
//

import CoreGraphics

// MARK: - MenuBarItemInfo

/// A simplified version of a menu bar item.
///
/// This type acts as a partial replacement for the original `MenuBarItemInfo`
/// type (now called ``MenuBarItemLegacyInfo``). Its purpose is to help regain
/// some of the functionality that was broken in macOS 26 Developer Beta 1.
///
/// A value of this type functions as a unique identifier for a single menu
/// bar item, and is mainly used for caching and comparison. Currently, the
/// only information this type contains is a CGWindowID corresponding to a
/// menu bar item's window, meaning that there are still instances where the
/// legacy type is needed. However, the hope is to build up this new type,
/// so that it can eventually replace the original.
struct MenuBarItemInfo: Hashable, CustomStringConvertible {
    /// The item's window identifier.
    let windowID: CGWindowID

    /// A textual representation of the item.
    var description: String {
        String(describing: windowID)
    }
}

// MARK: - MenuBarItemLegacyInfo

/// A simplified version of a menu bar item that was used as the primary way
/// to identify menu bar items until macOS 26 (Developer Beta 1).
///
/// See ``MenuBarItemInfo`` documentation for more details.
struct MenuBarItemLegacyInfo: Hashable, CustomStringConvertible {
    /// The namespace of the info's item.
    let namespace: Namespace

    /// The title of the info's item.
    let title: String

    /// A Boolean value that indicates whether the info's item can be moved.
    var isMovable: Bool {
        !MenuBarItemLegacyInfo.immovableItems.contains(self)
    }

    /// A Boolean value that indicates whether the info's item can be hidden.
    var canBeHidden: Bool {
        !MenuBarItemLegacyInfo.nonHideableItems.contains(self)
    }

    /// A string representation of the info.
    var stringValue: String {
        var result = namespace.rawValue
        if !title.isEmpty {
            result.append(":\(title)")
        }
        return result
    }

    /// A textual representation of the info.
    var description: String {
        stringValue
    }

    /// Creates info with the given namespace and title.
    init(namespace: Namespace, title: String) {
        self.namespace = namespace
        self.title = title
    }

    /// Creates info for the control item with the given identifier.
    private init(controlItem identifier: ControlItem.Identifier) {
        if #available(macOS 26.0, *) {
            self.init(namespace: .controlCenter, title: identifier.rawValue)
        } else {
            self.init(namespace: .ice, title: identifier.rawValue)
        }
    }
}

// MARK: MenuBarItemLegacyInfo Constants

extension MenuBarItemLegacyInfo {

    // MARK: Special Item Lists

    /// An array of infos for items whose movement is prevented by macOS.
    static let immovableItems = [clock, siri, controlCenter]

    // FIXME: At some point, Apple made the "MusicRecognition" item hideable.
    // We need to determine which version of macOS first had this change, and
    // conditionally exclude the item from this list based on that.
    //
    /// An array of infos for items that can be moved, but cannot be hidden.
    static let nonHideableItems = [audioVideoModule, faceTime, musicRecognition, screenCaptureUI]

    /// An array of infos for items representing Ice's control items.
    static let controlItems = ControlItem.Identifier.allCases.map { $0.legacyInfo }

    // MARK: Control Items

    /// Info for the control item for the visible section.
    static let iceIcon = MenuBarItemLegacyInfo(controlItem: .iceIcon)

    /// Info for the control item for the hidden section.
    static let hiddenControlItem = MenuBarItemLegacyInfo(controlItem: .hidden)

    /// Info for the control item for the always-hidden section.
    static let alwaysHiddenControlItem = MenuBarItemLegacyInfo(controlItem: .alwaysHidden)

    // MARK: Other Items

    /// Info for the "Clock" item.
    static let clock = MenuBarItemLegacyInfo(namespace: .controlCenter, title: "Clock")

    /// Info for the "Siri" item.
    static let siri: MenuBarItemLegacyInfo = {
        if #available(macOS 26.0, *) {
            MenuBarItemLegacyInfo(namespace: .controlCenter, title: "Siri")
        } else {
            MenuBarItemLegacyInfo(namespace: .systemUIServer, title: "Siri")
        }
    }()

    /// Info for the "Control Center" item.
    static let controlCenter: MenuBarItemLegacyInfo = {
        if #available(macOS 26.0, *) {
            MenuBarItemLegacyInfo(namespace: .controlCenter, title: "BentoBox-0")
        } else {
            MenuBarItemLegacyInfo(namespace: .controlCenter, title: "BentoBox")
        }
    }()

    /// Info for the item that appears in the menu bar while the screen or system
    /// audio is being recorded.
    static let audioVideoModule = MenuBarItemLegacyInfo(namespace: .controlCenter, title: "AudioVideoModule")

    /// Info for the "FaceTime" item.
    static let faceTime = MenuBarItemLegacyInfo(namespace: .controlCenter, title: "FaceTime")

    /// Info for the "MusicRecognition" (a.k.a. "Shazam") item.
    static let musicRecognition = MenuBarItemLegacyInfo(namespace: .controlCenter, title: "MusicRecognition")

    // FIXME: How do we reference this item in macOS 26?
    /// Info for the "stop recording" item that appears in the menu bar during screen
    /// recordings started by the macOS "Screenshot" tool.
    static let screenCaptureUI = MenuBarItemLegacyInfo(namespace: .screenCaptureUI, title: "Item-0")
}

// MARK: MenuBarItemLegacyInfo: Codable
extension MenuBarItemLegacyInfo: Codable {
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

// MARK: - MenuBarItemLegacyInfo.Namespace

extension MenuBarItemLegacyInfo {
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

// MARK: MenuBarItemLegacyInfo.Namespace Constants
extension MenuBarItemLegacyInfo.Namespace {
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
