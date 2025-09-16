//
//  MenuBarItemTag.swift
//  Ice
//

import CoreGraphics
import Foundation

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
        !MenuBarItemTag.nonHideableItems.contains(self) &&
        !(namespace.isUUID && title == "AudioVideoModule")
    }

    /// A Boolean value that indicates whether the item identified
    /// by this tag is a control item owned by Ice.
    var isControlItem: Bool {
        MenuBarItemTag.controlItems.contains(self)
    }

    /// A Boolean value that indicates whether the item identified
    /// by this tag is a "BentoBox" item owned by Control Center.
    var isBentoBox: Bool {
        namespace == .controlCenter && title.hasPrefix("BentoBox")
    }

    /// A Boolean value that indicates whether the item identified
    /// by this tag is a system-created clone of an actual item,
    /// and therefore invalid for management.
    var isSystemClone: Bool {
        namespace.isUUID && title == "System Status Item Clone"
    }

    /// A textual representation of the tag.
    var description: String {
        var result = String(describing: namespace)
        if !title.isEmpty {
            result.append(":\(title)")
        }
        return result
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
    ///
    /// These items have fixed positions at the trailing end of the menu bar,
    /// and cannot be hidden.
    ///
    /// In macOS 26, this list contains the "Clock" and "Control Center" items.
    /// In earlier releases, it also contained the "Siri" item.
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

    /// The tag for Ice's control item for the "Visible" section.
    static let visibleControlItem = MenuBarItemTag(controlItem: .visible)

    /// The tag for Ice's control item for the "Hidden" section.
    static let hiddenControlItem = MenuBarItemTag(controlItem: .hidden)

    /// The tag for Ice's control item for the "Always-Hidden" section.
    static let alwaysHiddenControlItem = MenuBarItemTag(controlItem: .alwaysHidden)

    // MARK: Other Special Items

    /// The tag for the system item that appears in the menu bar
    /// during screen or audio capture.
    static let audioVideoModule = MenuBarItemTag(namespace: .controlCenter, title: "AudioVideoModule")

    /// The tag for the system "Clock" item.
    static let clock = MenuBarItemTag(namespace: .controlCenter, title: "Clock")

    /// The tag for the system "Control Center" item.
    static let controlCenter = if #available(macOS 26.0, *) {
        MenuBarItemTag(namespace: .controlCenter, title: "BentoBox-0")
    } else {
        MenuBarItemTag(namespace: .controlCenter, title: "BentoBox")
    }

    /// The tag for the system "FaceTime" item.
    static let faceTime = MenuBarItemTag(namespace: .controlCenter, title: "FaceTime")

    /// The tag for the system "Music Recognition" item.
    static let musicRecognition = MenuBarItemTag(namespace: .controlCenter, title: "MusicRecognition")

    /// The tag for the system item that appears in the menu bar
    /// during recordings started by the macOS "Screenshot" tool.
    static let screenCaptureUI = MenuBarItemTag(namespace: .screenCaptureUI, title: "Item-0")

    /// The tag for the system "Siri" item.
    static let siri = MenuBarItemTag(namespace: .systemUIServer, title: "Siri")

    /// The tag for the system "Time Machine" item.
    static let timeMachine = if #available(macOS 26.0, *) {
        MenuBarItemTag(namespace: .systemUIServer, title: "com.apple.menuextra.TimeMachine")
    } else if #available(macOS 15.0, *) {
        MenuBarItemTag(namespace: .systemUIServer, title: "TimeMachineMenuExtra.TMMenuExtraHost")
    } else {
        MenuBarItemTag(namespace: .systemUIServer, title: "TimeMachine.TMMenuExtraHost")
    }
}

// MARK: - MenuBarItemTag.Namespace

extension MenuBarItemTag {
    /// A type that represents a menu bar item namespace.
    enum Namespace: Hashable, CustomStringConvertible {
        /// The `null` namespace.
        case null
        /// A namespace represented by a string.
        case string(String)
        /// A namespace represented by a UUID.
        case uuid(UUID)

        /// A textual representation of the namespace.
        var description: String {
            switch self {
            case .null: "null"
            case .string(let string): string
            case .uuid(let uuid): uuid.uuidString
            }
        }

        /// A Boolean value that indicates whether this namespace is
        /// the `null` namespace.
        var isNull: Bool {
            switch self {
            case .null: true
            case .string, .uuid: false
            }
        }

        /// A Boolean value that indicates whether this namespace is
        /// represented by a string.
        var isString: Bool {
            switch self {
            case .string: true
            case .uuid, .null: false
            }
        }

        /// A Boolean value that indicates whether this namespace is
        /// represented by a UUID.
        var isUUID: Bool {
            switch self {
            case .uuid: true
            case .null, .string: false
            }
        }

        /// Creates a namespace with the given optional value.
        ///
        /// - Parameter value: An optional value for the namespace.
        ///
        /// - Returns: A namespace represented by a string when `value`
        ///   is not `nil`. Otherwise, the `null` namespace.
        static func optional(_ value: String?) -> Namespace {
            value.map { .string($0) } ?? .null
        }
    }
}

// MARK: MenuBarItemTag.Namespace Constants
extension MenuBarItemTag.Namespace {
    /// The namespace for the "Ice" process.
    static let ice = string(Constants.bundleIdentifier)

    /// The namespace for the "Control Center" process.
    static let controlCenter = string("com.apple.controlcenter")

    /// The namespace for the "PasswordsMenuBarExtra" process.
    static let passwords = string("com.apple.Passwords.MenuBarExtra")

    /// The namespace for the "screencaptureui" process.
    static let screenCaptureUI = string("com.apple.screencaptureui")

    /// The namespace for the "SystemUIServer" process.
    static let systemUIServer = string("com.apple.systemuiserver")

    /// The namespace for the "TextInputMenuAgent" process.
    static let textInputMenuAgent = string("com.apple.TextInputMenuAgent")

    /// The namespace for the "WeatherMenu" process.
    static let weather = string("com.apple.weather.menu")
}
