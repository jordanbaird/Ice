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
        !MenuBarItemTag.nonHideableItems.contains(self)
    }

    /// A Boolean value that indicates whether the item identified
    /// by this tag is a control item owned by Ice.
    var isControlItem: Bool {
        MenuBarItemTag.controlItems.contains(self)
    }

    /// A string representation of the tag.
    var stringValue: String {
        var result = namespace.stringValue
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

    // MARK: Other System Items

    /// The tag for the system "Clock" item.
    static let clock = MenuBarItemTag(namespace: .controlCenter, title: "Clock")

    /// The tag for the system "Control Center" item.
    static let controlCenter = if #available(macOS 26.0, *) {
        MenuBarItemTag(namespace: .controlCenter, title: "BentoBox-0")
    } else {
        MenuBarItemTag(namespace: .controlCenter, title: "BentoBox")
    }

    /// The tag for the system "Siri" item.
    static let siri = MenuBarItemTag(namespace: .systemUIServer, title: "Siri")

    /// The tag for the system "Spotlight" item.
    static let spotlight = MenuBarItemTag(namespace: .spotlight, title: "Item-0")

    /// The tag for the system "WiFi" item.
    static let wifi = MenuBarItemTag(namespace: .controlCenter, title: "WiFi")

    /// The tag for the system "Bluetooth" item.
    static let bluetooth = MenuBarItemTag(namespace: .controlCenter, title: "Bluetooth")

    /// The tag for the system "Battery" item.
    static let battery = MenuBarItemTag(namespace: .controlCenter, title: "Battery")

    /// The tag for the system "Focus Modes" item.
    static let focusModes = MenuBarItemTag(namespace: .controlCenter, title: "FocusModes")

    /// The tag for the system "Screen Mirroring" item.
    static let screenMirroring = MenuBarItemTag(namespace: .controlCenter, title: "ScreenMirroring")

    /// The tag for the system "Display" item.
    static let display = MenuBarItemTag(namespace: .controlCenter, title: "Display")

    /// The tag for the system "Sound" item.
    static let sound = MenuBarItemTag(namespace: .controlCenter, title: "Sound")

    /// The tag for the system "Now Playing" item.
    static let nowPlaying = MenuBarItemTag(namespace: .controlCenter, title: "NowPlaying")

    /// The tag for the system "TimeMachine" item.
    static let timeMachine = if #available(macOS 15.0, *) {
        MenuBarItemTag(namespace: .systemUIServer, title: "TimeMachineMenuExtra.TMMenuExtraHost")
    } else {
        MenuBarItemTag(namespace: .systemUIServer, title: "TimeMachine.TMMenuExtraHost")
    }

    /// The tag for the item that appears in the menu bar while the screen
    /// or system audio is being recorded.
    static let audioVideoModule = MenuBarItemTag(namespace: .controlCenter, title: "AudioVideoModule")

    /// The tag for the system "FaceTime" item.
    static let faceTime = MenuBarItemTag(namespace: .controlCenter, title: "FaceTime")

    /// The tag for the system "MusicRecognition" item.
    static let musicRecognition = MenuBarItemTag(namespace: .controlCenter, title: "MusicRecognition")

    // TODO: How do we reference this item in macOS 26?
    /// The tag for the "stop recording" item that appears in the menu bar
    /// during screen recordings started by the macOS "Screenshot" tool.
    static let screenCaptureUI = MenuBarItemTag(namespace: .screenCaptureUI, title: "Item-0")
}

// MARK: - MenuBarItemTag.Namespace

extension MenuBarItemTag {
    /// A type that represents a menu bar item namespace.
    enum Namespace: Hashable, CustomStringConvertible {
        /// The null namespace.
        case null
        /// A namespace represented by string.
        case string(String)
        /// A namespace represented by uuid.
        case uuid(UUID)

        /// The namespace's string value.
        var stringValue: String {
            switch self {
            case .null: "null"
            case .string(let string): string
            case .uuid(let uuid): uuid.uuidString
            }
        }

        /// A textual representation of the namespace.
        var description: String {
            stringValue
        }

        /// Creates a namespace with the given optional value.
        /// 
        /// - Parameter value: An optional value for the namespace.
        ///
        /// - Returns: The ``string(_:)`` namespace when `value` is not `nil`.
        ///   Otherwise, the ``null`` namespace.
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

    /// The namespace for the "Spotlight" process.
    static let spotlight = string("com.apple.Spotlight")

    /// The namespace for the "SystemUIServer" process.
    static let systemUIServer = string("com.apple.systemuiserver")

    /// The namespace for the "TextInputMenuAgent" process.
    static let textInputMenuAgent = string("com.apple.TextInputMenuAgent")

    /// The namespace for the "WeatherMenu" process.
    static let weather = string("com.apple.weather.menu")
}
