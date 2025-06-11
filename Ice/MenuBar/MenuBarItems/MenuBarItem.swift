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

    /// The menu bar item info associated with this item.
    let info: MenuBarItemInfo

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
        info.isMovable
    }

    /// A Boolean value that indicates whether the item can be hidden.
    var canBeHidden: Bool {
        info.canBeHidden
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

        // Most items will use their computed "best name", but we need
        // to handle a few special cases.
        return switch info.namespace {
        case .passwords, .weather:
            // These need more searchable names.
            //
            //   "PasswordsMenuBarExtra" -> "Passwords"
            //   "WeatherMenu" -> "Weather"
            //
            // Convert to "Title Case" and take the first word.
            String(toTitleCase(bestName).prefix { !$0.isWhitespace })
        case .controlCenter where title == "BentoBox":
            bestName // "BentoBox" -> "Control Center"
        case .controlCenter where title == "WiFi":
            title // Keep "UpperCamelCase".
        case .controlCenter where title.hasPrefix("Hearing"):
            // Title of this item was changed to "Hearing_GlowE" in macOS 15.4.
            String(toTitleCase(title).prefix { $0.isLetter || $0.isNumber })
        case .systemUIServer where title.contains("TimeMachine"):
            // Title of this item depends on the macOS version.
            //
            //   Sonoma:  "TimeMachine.TMMenuExtraHost"
            //   Sequoia: "TimeMachineMenuExtra.TMMenuExtraHost"
            //
            // Keep things consistent and replace it.
            "Time Machine"
        case .controlCenter, .systemUIServer:
            // Most system items are owned by the same couple of apps, so use the
            // title instead of the app name. Some are "UpperCamelCase", some are
            // dot-separated. Prefix to the first dot and convert to "Title Case".
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
        String(describing: info)
    }

    /// The latest version of the menu bar item, or `nil` if the item
    /// no longer exists.
    var latest: MenuBarItem? {
        guard let window = WindowInfo(windowID: windowID) else {
            return nil
        }
        return MenuBarItem(uncheckedItemWindow: window)
    }

    /// Creates a menu bar item from the given window.
    ///
    /// This initializer does not perform any checks on the window to ensure that
    /// it is a valid menu bar item window. Only call this initializer if you are
    /// certain that the window is valid.
    private init(uncheckedItemWindow itemWindow: WindowInfo) {
        self.window = itemWindow
        self.info = MenuBarItemInfo(uncheckedItemWindow: itemWindow)
    }

    /// Returns the current frame for the item.
    func getCurrentFrame() -> CGRect? {
        return Bridging.getWindowFrame(for: windowID)
    }
}

// MARK: MenuBarItem Getters
extension MenuBarItem {
    /// Returns an array of the current menu bar items in the menu bar on the given display.
    ///
    /// - Parameters:
    ///   - display: The display to retrieve the menu bar items on. Pass `nil` to return the
    ///     menu bar items across all displays.
    ///   - onScreenOnly: A Boolean value that indicates whether only the menu bar items that
    ///     are on screen should be returned.
    ///   - activeSpaceOnly: A Boolean value that indicates whether only the menu bar items
    ///     that are on the active space should be returned.
    static func getMenuBarItems(on display: CGDirectDisplayID? = nil, onScreenOnly: Bool, activeSpaceOnly: Bool) -> [MenuBarItem] {
        var option: Bridging.WindowListOption = [.menuBarItems]

        var boundsPredicate: (CGWindowID) -> Bool = { _ in true }
        var spacePredicate: (CGWindowID) -> Bool = { _ in true }

        if onScreenOnly {
            option.insert(.onScreen)
            if let display {
                let displayBounds = CGDisplayBounds(display)
                boundsPredicate = { windowID in
                    if let frame = Bridging.getWindowFrame(for: windowID) {
                        return displayBounds.intersects(frame)
                    }
                    return false
                }
            }
        }
        if activeSpaceOnly {
            option.insert(.activeSpace)
            if let spaceID = display.flatMap(Bridging.getCurrentSpaceID) {
                spacePredicate = { windowID in
                    Bridging.isWindowOnSpace(windowID, spaceID)
                }
            }
        }

        return Bridging.getWindowList(option: option).lazy
            .compactMap { windowID in
                guard
                    boundsPredicate(windowID),
                    spacePredicate(windowID),
                    let window = WindowInfo(windowID: windowID)
                else {
                    return nil
                }
                return MenuBarItem(uncheckedItemWindow: window)
            }
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

// MARK: - MenuBarItemInfo Unchecked Item Window Initializer

private extension MenuBarItemInfo {
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

// MARK: - MenuBarItemInfo.Namespace Unchecked Item Window Initializer

private extension MenuBarItemInfo.Namespace {
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
