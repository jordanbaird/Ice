//
//  MenuBarItem.swift
//  Ice
//

import Cocoa

/// A structural representation of a menu bar item.
struct MenuBarItem: CustomStringConvertible {
    /// The tag associated with this item.
    let tag: MenuBarItemTag

    /// The item's window identifier.
    let windowID: CGWindowID

    /// The identifier of the process that owns the item.
    let ownerPID: pid_t

    /// The identifier of the process that created the item.
    let sourcePID: pid_t?

    /// The item's bounds, specified in screen coordinates.
    let bounds: CGRect

    /// The item's window title.
    let title: String?

    /// Live status information published by the item's Accessibility element.
    /// These values let macOS 27 reproduce status-bar content without falling
    /// back to the owning application's unrelated app icon.
    let accessibilityHelp: String?
    let accessibilityValue: String?

    /// A Boolean value that indicates whether the item is on screen.
    let isOnScreen: Bool

    /// Creates a structural item from a non-WindowServer provider.
    ///
    /// macOS 27 menu bar items are composited by MenuBarAgent and no longer
    /// have individual WindowServer windows, so the accessibility provider
    /// supplies these fields directly.
    init(
        tag: MenuBarItemTag,
        windowID: CGWindowID,
        ownerPID: pid_t,
        sourcePID: pid_t?,
        bounds: CGRect,
        title: String?,
        accessibilityHelp: String? = nil,
        accessibilityValue: String? = nil,
        isOnScreen: Bool
    ) {
        self.tag = tag
        self.windowID = windowID
        self.ownerPID = ownerPID
        self.sourcePID = sourcePID
        self.bounds = bounds
        self.title = title
        self.accessibilityHelp = accessibilityHelp
        self.accessibilityValue = accessibilityValue
        self.isOnScreen = isOnScreen
    }

    /// A Boolean value that indicates whether this item can be moved.
    var isMovable: Bool {
        tag.isMovable
    }

    /// A Boolean value that indicates whether this item can be hidden.
    var canBeHidden: Bool {
        tag.canBeHidden
    }

    /// A Boolean value that indicates whether this item is one of Ice's
    /// control items.
    var isControlItem: Bool {
        tag.isControlItem
    }

    /// A Boolean value that indicates whether this item is a "BentoBox"
    /// item owned by the Control Center.
    var isBentoBox: Bool {
        tag.isBentoBox
    }

    /// A Boolean value that indicates whether this item is a
    /// system-created clone of an actual item, and therefore invalid
    /// for management.
    var isSystemClone: Bool {
        tag.isSystemClone
    }

    /// The application that owns the item.
    ///
    /// - Note: In macOS 26 and later, this property always returns the
    ///   Control Center. To get the actual application that created the
    ///   item, use ``sourceApplication``.
    var owningApplication: NSRunningApplication? {
        NSRunningApplication(processIdentifier: ownerPID)
    }

    /// The application that created the item.
    ///
    /// - Note: Prior to macOS 26, this property and ``owningApplication``
    ///   are functionally equivalent.
    var sourceApplication: NSRunningApplication? {
        guard let sourcePID else {
            return nil
        }
        return NSRunningApplication(processIdentifier: sourcePID)
    }

    // TODO: Generate this once, during initialization.
    /// A name associated with the item, suited for display.
    var displayName: String {
        /// Converts "UpperCamelCase" to "Title Case".
        ///
        /// Ignores cases where a single lowercase letter immediately
        /// precedes an uppercase letter (i.e. "WiFi").
        func toTitleCase<S: StringProtocol>(_ s: S) -> String {
            String(s).replacing(/([a-z]{2})([A-Z])/) { $0.output.1 + " " + $0.output.2 }
        }

        guard !isControlItem else {
            return Constants.displayName
        }

        lazy var fallbackName = "Menu Bar Item"

        guard let sourceApplication else {
            return fallbackName
        }

        lazy var sourceName = sourceApplication.localizedName ?? sourceApplication.bundleIdentifier

        guard let title else {
            return sourceName ?? fallbackName
        }

        lazy var bestName = sourceName ?? title

        // macOS 27 hosts Spotlight in the `com.apple.campo` process, whose
        // localized application name is "Siri" on current seeds. Prefer the
        // button's own AX title so Layout does not label the magnifying-glass
        // status item as Siri.
        if sourceApplication.bundleIdentifier == "com.apple.campo" {
            let normalizedTitle = title.lowercased()
            if normalizedTitle.contains("spotlight") ||
                normalizedTitle.contains("search") ||
                title.contains("搜索")
            {
                return title
            }
        }

        guard !isBentoBox else {
            if tag == .controlCenter {
                return bestName
            }
            return title
        }

        // Most items use their computed "best name", but we handle
        // a few special cases for system items.
        let displayName = switch tag.namespace {
        case .passwords, .weather, .textInputMenuAgent:
            // "PasswordsMenuBarExtra" -> "Passwords"
            // "WeatherMenu" -> "Weather"
            // "TextInputMenuAgent" -> "Text Input"
            toTitleCase(bestName.replacing(/Menu.*/, with: ""))
        case .controlCenter:
            if let match = title.prefixMatch(of: /Hearing/) {
                // Changed from "Hearing" to "Hearing_GlowE" in macOS 15.4
                toTitleCase(match.output)
            } else {
                toTitleCase(title)
            }
        case .systemUIServer:
            if let match = title.firstMatch(of: /TimeMachine/) {
                // Sonoma:  "TimeMachine.TMMenuExtraHost"
                // Sequoia: "TimeMachineMenuExtra.TMMenuExtraHost"
                // Tahoe:   "com.apple.menuextra.TimeMachine"
                toTitleCase(match.output)
            } else {
                toTitleCase(title)
            }
        default:
            bestName
        }

        // Provide some extra context if the name is just a UUID.
        if UUID(uuidString: displayName) != nil, let sourceName {
            return "\(sourceName) (\(displayName))"
        }

        return displayName
    }

    /// A textual representation of the item.
    var description: String {
        "\(displayName) (\(tag))"
    }

    /// A string to use for logging purposes.
    var logString: String {
        "<\(tag) (windowID: \(windowID))>"
    }

    /// Creates a menu bar item without checks.
    ///
    /// This initializer does not perform validity checks on its parameters.
    /// Only call it if you are certain the window is a valid menu bar item.
    private init(uncheckedItemWindow itemWindow: WindowInfo) {
        self.tag = MenuBarItemTag(uncheckedItemWindow: itemWindow)
        self.windowID = itemWindow.windowID
        self.ownerPID = itemWindow.ownerPID
        self.sourcePID = itemWindow.ownerPID
        self.bounds = itemWindow.bounds
        self.title = itemWindow.title
        self.accessibilityHelp = nil
        self.accessibilityValue = nil
        self.isOnScreen = itemWindow.isOnScreen
    }

    /// Creates a menu bar item without checks.
    ///
    /// This initializer does not perform validity checks on its parameters.
    /// Only call it if you are certain the window is a valid menu bar item
    /// and the source pid belongs to the application that created it.
    @available(macOS 26.0, *)
    private init(uncheckedItemWindow itemWindow: WindowInfo, sourcePID: pid_t?) {
        self.tag = MenuBarItemTag(uncheckedItemWindow: itemWindow, sourcePID: sourcePID)
        self.windowID = itemWindow.windowID
        self.ownerPID = itemWindow.ownerPID
        self.sourcePID = sourcePID
        self.bounds = itemWindow.bounds
        self.title = itemWindow.title
        self.accessibilityHelp = nil
        self.accessibilityValue = nil
        self.isOnScreen = itemWindow.isOnScreen
    }
}

// MARK: - MenuBarItem List

extension MenuBarItem {
    /// Options that specify the menu bar items in a list.
    struct ListOption: OptionSet {
        let rawValue: Int

        /// Specifies menu bar items that are currently on screen.
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
        var bridgingOption: Bridging.MenuBarWindowListOption = .itemsOnly
        var displayBoundsPredicate: (CGWindowID) -> Bool = { _ in true }

        if let display {
            bridgingOption.insert(.onScreen)
            let displayBounds = CGDisplayBounds(display)
            displayBoundsPredicate = { windowID in
                Bridging.windowIntersectsDisplayBounds(windowID, displayBounds)
            }
        } else if option.contains(.onScreen) {
            bridgingOption.insert(.onScreen)
        }
        if option.contains(.activeSpace) {
            bridgingOption.insert(.activeSpace)
        }

        return Bridging.getMenuBarWindowList(option: bridgingOption)
            .reversed().compactMap { windowID in
                guard
                    displayBoundsPredicate(windowID),
                    let window = WindowInfo(windowID: windowID)
                else {
                    return nil
                }
                return window
            }
    }

    /// Creates and returns a list of menu bar items using experimental
    /// source pid retrieval for macOS 26.
    @available(macOS 26.0, *)
    private static func getMenuBarItemsExperimental(on display: CGDirectDisplayID?, option: ListOption) async -> [MenuBarItem] {
        var items = [MenuBarItem]()
        for window in getMenuBarItemWindows(on: display, option: option) {
            let sourcePID = await MenuBarItemService.Connection.shared.sourcePID(for: window)
            let item = MenuBarItem(uncheckedItemWindow: window, sourcePID: sourcePID)
            items.append(item)
        }
        return items
    }

    /// Creates and returns a list of menu bar items, defaulting to the
    /// legacy source pid behavior, prior to macOS 26.
    private static func getMenuBarItemsLegacyMethod(on display: CGDirectDisplayID?, option: ListOption) -> [MenuBarItem] {
        getMenuBarItemWindows(on: display, option: option).map { window in
            MenuBarItem(uncheckedItemWindow: window)
        }
    }

    /// Creates and returns a list of menu bar items for the given display.
    ///
    /// - Parameters:
    ///   - display: An identifier for a display. Pass `nil` to return the menu bar
    ///     items across all available displays.
    ///   - option: Options that filter the returned list. Pass an empty option set
    ///     to return all available menu bar items.
    static func getMenuBarItems(on display: CGDirectDisplayID? = nil, option: ListOption) async -> [MenuBarItem] {
        if #available(macOS 27.0, *) {
            return await Task.detached(priority: .userInitiated) {
                MacOS27MenuBarItemProvider.menuBarItems(on: display, option: option)
            }.value
        } else if #available(macOS 26.0, *) {
            return await getMenuBarItemsExperimental(on: display, option: option)
        } else {
            return getMenuBarItemsLegacyMethod(on: display, option: option)
        }
    }
}

// MARK: MenuBarItem: Equatable
extension MenuBarItem: Equatable {
    static func == (lhs: MenuBarItem, rhs: MenuBarItem) -> Bool {
        lhs.tag == rhs.tag &&
        lhs.windowID == rhs.windowID &&
        lhs.ownerPID == rhs.ownerPID &&
        lhs.sourcePID == rhs.sourcePID &&
        NSStringFromRect(lhs.bounds) == NSStringFromRect(rhs.bounds) &&
        lhs.title == rhs.title &&
        lhs.accessibilityHelp == rhs.accessibilityHelp &&
        lhs.accessibilityValue == rhs.accessibilityValue &&
        lhs.isOnScreen == rhs.isOnScreen
    }
}

// MARK: MenuBarItem: Hashable
extension MenuBarItem: Hashable {
    func hash(into hasher: inout Hasher) {
        hasher.combine(tag)
        hasher.combine(windowID)
        hasher.combine(ownerPID)
        hasher.combine(sourcePID)
        hasher.combine(NSStringFromRect(bounds))
        hasher.combine(title)
        hasher.combine(accessibilityHelp)
        hasher.combine(accessibilityValue)
        hasher.combine(isOnScreen)
    }
}

// MARK: - MenuBarItemTag Helper

private extension MenuBarItemTag {
    /// Creates a tag without checks.
    ///
    /// This initializer does not perform validity checks on its parameters.
    /// Only call it if you are certain the window is a valid menu bar item.
    init(uncheckedItemWindow itemWindow: WindowInfo) {
        self.namespace = Namespace(uncheckedItemWindow: itemWindow)
        self.title = itemWindow.title ?? ""
        self.instanceIndex = 0
    }

    /// Creates a tag without checks.
    ///
    /// This initializer does not perform validity checks on its parameters.
    /// Only call it if you are certain the window is a valid menu bar item
    /// and the source pid belongs to the application that created it.
    @available(macOS 26.0, *)
    init(uncheckedItemWindow itemWindow: WindowInfo, sourcePID: pid_t?) {
        self.namespace = Namespace(uncheckedItemWindow: itemWindow, sourcePID: sourcePID)
        self.title = itemWindow.title ?? ""
        self.instanceIndex = 0
    }
}

// MARK: - MenuBarItemTag.Namespace Helper

private extension MenuBarItemTag.Namespace {
    private static var uuidCache = [CGWindowID: UUID]()

    /// Creates a namespace without checks.
    ///
    /// This initializer does not perform validity checks on its parameters.
    /// Only call it if you are certain the window is a valid menu bar item.
    init(uncheckedItemWindow itemWindow: WindowInfo) {
        // Most apps have a bundle ID, but we should be able to handle apps
        // that don't. We should also be able to handle daemons and helpers,
        // which are more likely not to have a bundle ID.
        //
        // Use the name of the owning process as a fallback. The non-localized
        // name seems less likely to change, so let's prefer it as a (somewhat)
        // stable identifier.
        if let app = itemWindow.owningApplication {
            self = .optional(app.bundleIdentifier ?? itemWindow.ownerName ?? app.localizedName)
        } else {
            self = .optional(itemWindow.ownerName)
        }
    }

    /// Creates a namespace without checks.
    ///
    /// This initializer does not perform validity checks on its parameters.
    /// Only call it if you are certain the window is a valid menu bar item
    /// and the source pid belongs to the application that created it.
    @available(macOS 26.0, *)
    init(uncheckedItemWindow itemWindow: WindowInfo, sourcePID: pid_t?) {
        // Most apps have a bundle ID, but we should be able to handle apps
        // that don't. We should also be able to handle daemons and helpers,
        // which are more likely not to have a bundle ID.
        if let sourcePID, let app = NSRunningApplication(processIdentifier: sourcePID) {
            self = .optional(app.bundleIdentifier ?? app.localizedName)
        } else if let uuid = Self.uuidCache[itemWindow.windowID] {
            self = .uuid(uuid)
        } else {
            let uuid = UUID()
            Self.uuidCache[itemWindow.windowID] = uuid
            self = .uuid(uuid)
        }
    }
}
