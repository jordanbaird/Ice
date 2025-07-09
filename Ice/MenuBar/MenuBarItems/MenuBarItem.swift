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

    /// The legacy menu bar item info associated with this item.
    let legacyInfo: MenuBarItemLegacyInfo

    /// The menu bar item info associated with this item.
    let info: MenuBarItemInfo

    /// The identifier of the item's window.
    var windowID: CGWindowID {
        window.windowID
    }

    /// The bounds of the item's window.
    var bounds: CGRect {
        window.bounds
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
        legacyInfo.isMovable
    }

    /// A Boolean value that indicates whether the item can be hidden.
    var canBeHidden: Bool {
        legacyInfo.canBeHidden
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

    /// A name associated with the item that is suited for display.
    var displayName: String {
        /// Converts "UpperCamelCase" to "Title Case".
        func toTitleCase<S: StringProtocol>(_ s: S) -> String {
            String(s).replacing(/([a-z])([A-Z])/) { $0.output.1 + " " + $0.output.2 }
        }

        var bestName: String {
            var fallback: String { "Unknown" }
            return if #available(macOS 26.0, *) {
                title ?? ownerName ?? fallback
            } else if let owningApplication {
                owningApplication.localizedName ??
                ownerName ??
                owningApplication.bundleIdentifier ??
                title ??
                fallback
            } else {
                ownerName ?? title ?? fallback
            }
        }

        guard #unavailable(macOS 26.0), let title else {
            return bestName
        }

        // Most items will use their computed "best name", but we need to
        // handle a few special cases for system items.
        return switch legacyInfo.namespace {
        case .passwords, .weather:
            // "PasswordsMenuBarExtra" -> "Passwords"
            // "WeatherMenu" -> "Weather"
            String(toTitleCase(bestName).prefix { !$0.isWhitespace })
        case .controlCenter where title.hasPrefix("BentoBox"):
            bestName
        case .controlCenter where title == "WiFi":
            title
        case .controlCenter where title.hasPrefix("Hearing"):
            // Title of this item was changed to "Hearing_GlowE" in macOS 15.4.
            String(toTitleCase(title).prefix { $0.isLetter || $0.isNumber })
        case .systemUIServer where title.contains("TimeMachine"):
            // Sonoma:  "TimeMachine.TMMenuExtraHost"
            // Sequoia: "TimeMachineMenuExtra.TMMenuExtraHost"
            "Time Machine"
        case .controlCenter, .systemUIServer:
            // Most system items are hosted by one of these two apps. They
            // usually have descriptive, but unformatted titles, so we'll do
            // some basic formatting ourselves.
            toTitleCase(title.prefix { $0 != "." })
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
        "<\(legacyInfo) (windowID: \(windowID))>"
    }

    /// Creates a menu bar item from the given window.
    ///
    /// This initializer does not perform any checks on the window to ensure that
    /// it is a valid menu bar item window. Only call this initializer if you are
    /// certain that the window is valid.
    private init(uncheckedItemWindow itemWindow: WindowInfo) {
        self.window = itemWindow
        self.legacyInfo = MenuBarItemLegacyInfo(uncheckedItemWindow: itemWindow)
        self.info = MenuBarItemInfo(windowID: itemWindow.windowID)
    }
}

// MARK: - MenuBarItem List

extension MenuBarItem {
    /// Options that specify the menu bar items in a list.
    struct ListOption: OptionSet {
        let rawValue: Int

        /// Specifies menu bar items that are currently on-screen.
        static let onScreen = ListOption(rawValue: 1 << 0)

        /// Specifies menu bar items on the currently active space.
        static let activeSpace = ListOption(rawValue: 1 << 1)
    }

    /// Creates and returns a list of menu bar items windows for the given display.
    ///
    /// - Parameters:
    ///   - display: An identifier for a display. Pass `nil` to return the menu bar
    ///     item windows across all available displays.
    ///   - option: Options that filter the returned list. Pass an empty option set
    ///     to return all available menu bar item windows.
    static func getMenuBarItemWindows(on display: CGDirectDisplayID? = nil, option: ListOption) -> [WindowInfo] {
        var bridgingOption: Bridging.WindowListOption = .menuBarItems

        var onScreenPredicate: (CGWindowID) -> Bool = { _ in true }
        var activeSpacePredicate: (CGWindowID) -> Bool = { _ in true }

        if option.contains(.onScreen) {
            bridgingOption.insert(.onScreen)
            if let display {
                let displayBounds = CGDisplayBounds(display)
                onScreenPredicate = { windowID in
                    if let bounds = Bridging.getWindowBounds(for: windowID) {
                        return displayBounds.intersects(bounds)
                    }
                    return false
                }
            }
        }
        if option.contains(.activeSpace) {
            bridgingOption.insert(.activeSpace)
            if let spaceID = display.flatMap(Bridging.getCurrentSpaceID) {
                activeSpacePredicate = { windowID in
                    Bridging.isWindowOnSpace(windowID, spaceID)
                }
            }
        }

        return Bridging.getWindowList(option: bridgingOption)
            .reversed().compactMap { windowID in
                guard
                    onScreenPredicate(windowID),
                    activeSpacePredicate(windowID),
                    let window = WindowInfo(windowID: windowID)
                else {
                    return nil
                }
                return window
            }
    }

    /// Creates and returns a list of menu bar items for the given display.
    ///
    /// - Parameters:
    ///   - display: An identifier for a display. Pass `nil` to return the menu bar
    ///     items across all available displays.
    ///   - option: Options that filter the returned list. Pass an empty option set
    ///     to return all available menu bar items.
    static func getMenuBarItems(on display: CGDirectDisplayID? = nil, option: ListOption) -> [MenuBarItem] {
        getMenuBarItemWindows(on: display, option: option).map { window in
            MenuBarItem(uncheckedItemWindow: window)
        }
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

// MARK: - MenuBarItemLegacyInfo Unchecked Item Window Initializer

private extension MenuBarItemLegacyInfo {
    /// Creates a simplified item from the given window.
    ///
    /// This initializer does not perform any checks on the window to ensure that
    /// it is a valid menu bar item window. Only call this initializer if you are
    /// certain that the window is valid.
    init(uncheckedItemWindow itemWindow: WindowInfo) {
        self.namespace = Namespace(uncheckedItemWindow: itemWindow)
        self.title = itemWindow.title ?? ""
    }
}

// MARK: - MenuBarItemLegacyInfo.Namespace Unchecked Item Window Initializer

private extension MenuBarItemLegacyInfo.Namespace {
    /// Creates a namespace from the given window.
    ///
    /// This initializer does not perform any checks on the window to ensure that
    /// it is a valid menu bar item window. Only call this initializer if you are
    /// certain that the window is valid.
    init(uncheckedItemWindow itemWindow: WindowInfo) {
        // Most apps have a bundle ID, but we should be able to handle apps
        // that don't. We should also be able to handle daemons and helpers,
        // which are more likely not to have a bundle ID.
        //
        // Use the name of the owning process as a fallback. The non-localized
        // name seems less likely to change, so let's prefer it as a (somewhat)
        // stable identifier.
        if let app = itemWindow.owningApplication {
            self.init(app.bundleIdentifier ?? itemWindow.ownerName ?? app.localizedName)
        } else {
            self.init(itemWindow.ownerName)
        }
    }
}
