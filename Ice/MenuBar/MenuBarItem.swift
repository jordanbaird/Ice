//
//  MenuBarItem.swift
//  Ice
//

import Cocoa

// MARK: - MenuBarItem

/// A representation of an item in the menu bar.
struct MenuBarItem {
    /// The item's window.
    let window: WindowInfo

    /// The identifier of the item's window.
    var windowID: CGWindowID {
        window.windowID
    }

    /// The frame of the item's window.
    var frame: CGRect {
        window.frame
    }

    /// The title of the item's window.
    var title: String? {
        window.title
    }

    /// A Boolean value that indicates whether the item is on screen.
    var isOnScreen: Bool {
        window.isOnScreen
    }

    /// A Boolean value that indicates whether the item can be moved.
    var isMovable: Bool {
        let immovableItems = Set(MenuBarItemInfo.immovableItems)
        return !immovableItems.contains(info)
    }

    /// A Boolean value that indicates whether the item can be hidden.
    var canBeHidden: Bool {
        let nonHideableItems = Set(MenuBarItemInfo.nonHideableItems)
        return !nonHideableItems.contains(info)
    }

    /// The process identifier of the application that owns the item.
    var ownerPID: pid_t {
        window.ownerPID
    }

    /// The name of the application that owns the item.
    ///
    /// This may have a value when ``owningApplication`` does not have
    /// a localized name.
    var ownerName: String? {
        window.ownerName
    }

    /// The application that owns the item.
    var owningApplication: NSRunningApplication? {
        window.owningApplication
    }

    /// The menu bar item info associated with this item.
    var info: MenuBarItemInfo {
        MenuBarItemInfo(item: self)
    }

    /// A name associated with the item that is suited for display to
    /// the user.
    var displayName: String {
        var fallback: String { "Unknown" }
        guard let owningApplication else {
            return ownerName ?? title ?? fallback
        }
        var bestName: String {
            owningApplication.localizedName ??
            ownerName ??
            owningApplication.bundleIdentifier ??
            fallback
        }
        guard let title else {
            return bestName
        }
        // by default, use the application name, but handle a few special cases
        return switch MenuBarItemInfo.Namespace(owningApplication.bundleIdentifier) {
        case .controlCenter:
            switch title {
            case "AccessibilityShortcuts": "Accessibility Shortcuts"
            case "BentoBox": bestName // Control Center
            case "FocusModes": "Focus"
            case "KeyboardBrightness": "Keyboard Brightness"
            case "MusicRecognition": "Music Recognition"
            case "NowPlaying": "Now Playing"
            case "ScreenMirroring": "Screen Mirroring"
            case "StageManager": "Stage Manager"
            case "UserSwitcher": "Fast User Switching"
            case "WiFi": "Wi-Fi"
            default: title
            }
        case .systemUIServer:
            switch title {
            case "TimeMachine.TMMenuExtraHost"/*Sonoma*/, "TimeMachineMenuExtra.TMMenuExtraHost"/*Sequoia*/: "Time Machine"
            default: title
            }
        case MenuBarItemInfo.Namespace("com.apple.Passwords.MenuBarExtra"): "Passwords"
        default:
            bestName
        }
    }

    /// A Boolean value that indicates whether the item is currently
    /// in the menu bar.
    var isCurrentlyInMenuBar: Bool {
        let list = Set(Bridging.getWindowList(option: .menuBarItems))
        return list.contains(windowID)
    }

    /// A string to use for logging purposes.
    var logString: String {
        String(describing: info)
    }

    /// Creates a menu bar item from the given window.
    ///
    /// This initializer does not perform any checks on the window to ensure that
    /// it is a valid menu bar item window. Only call this initializer if you are
    /// certain that the window is valid.
    private init(uncheckedItemWindow itemWindow: WindowInfo) {
        self.window = itemWindow
    }

    /// Creates a menu bar item.
    ///
    /// The parameters passed into this initializer are verified during the menu
    /// bar item's creation. If `itemWindow` does not represent a menu bar item,
    /// the initializer will fail.
    ///
    /// - Parameter itemWindow: A window that contains information about the item.
    private init?(itemWindow: WindowInfo) {
        guard itemWindow.isMenuBarItem else {
            return nil
        }
        self.init(uncheckedItemWindow: itemWindow)
    }

    /// Creates a menu bar item with the given window identifier.
    ///
    /// The parameters passed into this initializer are verified during the menu
    /// bar item's creation. If `windowID` does not represent a menu bar item,
    /// the initializer will fail.
    ///
    /// - Parameter windowID: An identifier for a window that contains information
    ///   about the item.
    private init?(windowID: CGWindowID) {
        guard let window = WindowInfo(windowID: windowID) else {
            return nil
        }
        self.init(itemWindow: window)
    }
}

// MARK: MenuBarItem Getters
extension MenuBarItem {
    /// Returns an array of menu bar items in the menu bar for the given display.
    static func getMenuBarItemsCoreGraphics(for display: CGDirectDisplayID, onScreenOnly: Bool) -> [MenuBarItem] {
        let windows = if onScreenOnly {
            WindowInfo.getOnScreenWindows(excludeDesktopWindows: true)
        } else {
            WindowInfo.getAllWindows(excludeDesktopWindows: true)
        }
        guard let menuBarWindow = WindowInfo.getMenuBarWindow(from: windows, for: display) else {
            return []
        }
        return windows.lazy
            .compactMap { window in
                guard
                    window.isMenuBarItem,
                    window.title != "",
                    window.frame.minY == menuBarWindow.frame.minY,
                    window.frame.maxY == menuBarWindow.frame.maxY
                else {
                    return nil
                }
                return MenuBarItem(uncheckedItemWindow: window)
            }
            .sortedByOrderInMenuBar()
    }

    /// Returns an array of menu bar items using private APIs to retrieve the
    /// windows.
    ///
    /// - Parameter onScreenOnly: A Boolean value that indicates whether only
    ///   the items that are on screen should be returned.
    static func getMenuBarItemsPrivateAPI(for display: CGDirectDisplayID, onScreenOnly: Bool) -> [MenuBarItem] {
        var option: Bridging.WindowListOption = [.menuBarItems]
        if onScreenOnly {
            option.insert(.onScreen)
        }
        let displayBounds = CGDisplayBounds(display)
        return Bridging.getWindowList(option: option).lazy
            .compactMap { windowID in
                guard
                    let windowFrame = Bridging.getWindowFrame(for: windowID),
                    displayBounds.intersects(windowFrame)
                else {
                    return nil
                }
                return MenuBarItem(windowID: windowID)
            }
            .sortedByOrderInMenuBar()
    }

    /// Returns an array of menu bar items using private APIs to retrieve
    /// the windows.
    ///
    /// - Parameters:
    ///   - onScreenOnly: A Boolean value that indicates whether only the
    ///     items that are on screen should be returned.
    ///   - activeSpaceOnly: A Boolean value that indicates whether only the
    ///     items that are on the active space should be returned.
    static func getMenuBarItemsPrivateAPI(onScreenOnly: Bool, activeSpaceOnly: Bool) -> [MenuBarItem] {
        var option: Bridging.WindowListOption = [.menuBarItems]
        if onScreenOnly {
            option.insert(.onScreen)
        }
        var titlePredicate: (MenuBarItem) -> Bool = { _ in true }
        if activeSpaceOnly {
            option.insert(.activeSpace)
            titlePredicate = { $0.title != "" }
        }
        return Bridging.getWindowList(option: option).lazy
            .compactMap { windowID in
                MenuBarItem(windowID: windowID)
            }
            .filter(titlePredicate)
            .sortedByOrderInMenuBar()
    }
}

// MARK: MenuBarItem: Equatable
extension MenuBarItem: Equatable {
    static func == (lhs: MenuBarItem, rhs: MenuBarItem) -> Bool {
        lhs.window == rhs.window
    }
}

// MARK: MenuBarItem: Hashable
extension MenuBarItem: Hashable {
    func hash(into hasher: inout Hasher) {
        hasher.combine(window)
    }
}

// MARK: - MenuBarItemInfo

/// A type that contains a simplified version of a menu bar item.
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

    /// Creates a simplified item from the given window.
    ///
    /// This initializer does not perform any checks on the window to ensure that
    /// it is a valid menu bar item window. Only call this initializer if you are
    /// certain that the window is valid.
    fileprivate init(uncheckedItemWindow itemWindow: WindowInfo) {
        if let bundleIdentifier = itemWindow.owningApplication?.bundleIdentifier {
            self.namespace = Namespace(bundleIdentifier)
        } else {
            self.namespace = .null
        }
        if let title = itemWindow.title {
            self.title = title
        } else {
            self.title = ""
        }
    }

    /// Creates a simplified item from the given menu bar item.
    init(item: MenuBarItem) {
        self.init(uncheckedItemWindow: item.window)
    }
}

// MARK: MenuBarItemInfo Constants
extension MenuBarItemInfo {
    /// An array of items whose movement is prevented by macOS.
    static let immovableItems = [clock, siri, controlCenter]

    /// An array of items that can be moved, but cannot be hidden.
    static let nonHideableItems = [audioVideoModule, faceTime, musicRecognition]

    /// Information for an item that represents the Ice icon.
    static let iceIcon = MenuBarItemInfo(
        namespace: .ice,
        title: ControlItem.Identifier.iceIcon.rawValue
    )

    /// Information for an item that represents the "Hidden" control item.
    static let hiddenControlItem = MenuBarItemInfo(
        namespace: .ice,
        title: ControlItem.Identifier.hidden.rawValue
    )

    /// Information for an item that represents the "Always Hidden" control item.
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
        try container.encode(String(describing: self))
    }
}

// MARK: MenuBarItemInfo.Namespace
extension MenuBarItemInfo {
    /// A type that represents a menu bar item namespace.
    struct Namespace: Codable, Hashable, RawRepresentable, CustomStringConvertible {
        private enum Kind {
            case null
            case rawValue(String)
        }

        private let kind: Kind

        var rawValue: String {
            switch kind {
            case .null: "<null>"
            case .rawValue(let rawValue): rawValue
            }
        }

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

        private init(kind: Kind) {
            self.kind = kind
        }

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
            if let value {
                self.init(rawValue: value)
            } else {
                self.init(kind: .null)
            }
        }

        /// The namespace for menu bar items owned by Ice.
        static let ice = Namespace(Bundle.main.bundleIdentifier)

        /// The namespace for menu bar items owned by Control Center.
        static let controlCenter = Namespace("com.apple.controlcenter")

        /// The namespace for menu bar items owned by the System UI Server.
        static let systemUIServer = Namespace("com.apple.systemuiserver")

        /// The namespace for special items.
        static let special = Namespace("Special")

        /// The null namespace.
        static let null = Namespace(kind: .null)
    }
}
