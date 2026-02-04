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
        self.info = MenuBarItemInfo(uncheckedItemWindow: itemWindow)
    }

    private static let logger = Logger(category: "MenuBarItem")
    
    /// Creates a menu bar item.
    ///
    /// The parameters passed into this initializer are verified during the menu
    /// bar item's creation. If `itemWindow` does not represent a menu bar item,
    /// the initializer will fail.
    ///
    /// - Parameter itemWindow: A window that contains information about the item.
    init?(itemWindow: WindowInfo) {
        // Debug: log Ice's own windows that fail isMenuBarItem check
        if itemWindow.owningApplication == .current && !itemWindow.isMenuBarItem {
            Self.logger.debug("Ice window failed isMenuBarItem: layer=\(itemWindow.layer), expected=\(Int(kCGStatusWindowLevel)), title=\(itemWindow.title ?? "nil")")
        }
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
    init?(windowID: CGWindowID) {
        guard let window = WindowInfo(windowID: windowID) else {
            Self.logger.debug("WindowInfo init failed for windowID: \(windowID)")
            return nil
        }
        // Debug: log if this is an Ice window
        if window.owningApplication == .current {
            Self.logger.debug("Found Ice window: windowID=\(windowID), layer=\(window.layer), title=\(window.title ?? "nil"), isMenuBarItem=\(window.isMenuBarItem)")
        }
        self.init(itemWindow: window)
    }
    
    /// Creates a menu bar item directly from a ControlItem's button frame.
    /// This is used for macOS 26+ where CGWindowListCreateDescriptionFromArray
    /// doesn't work with the new window ID format.
    ///
    /// - Parameters:
    ///   - buttonFrame: The button's frame in screen coordinates.
    ///   - windowID: The window ID.
    ///   - sectionName: The section name (used to determine the control item identifier).
    @MainActor
    init?(buttonFrame: CGRect, windowID: CGWindowID, sectionName: MenuBarSection.Name) {
        // Convert to the coordinate system used by CGWindowList (origin at top-left)
        guard let screen = NSScreen.main else {
            return nil
        }
        let frame = CGRect(
            x: buttonFrame.origin.x,
            y: screen.frame.height - buttonFrame.origin.y - buttonFrame.height,
            width: buttonFrame.width,
            height: buttonFrame.height
        )
        let title: String = switch sectionName {
        case .visible: ControlItem.Identifier.iceIcon.rawValue
        case .hidden: ControlItem.Identifier.hidden.rawValue
        case .alwaysHidden: ControlItem.Identifier.alwaysHidden.rawValue
        }
        let ownerPID = ProcessInfo.processInfo.processIdentifier
        
        // Create MenuBarItemInfo directly
        let info = MenuBarItemInfo(
            namespace: .ice,
            title: title
        )
        
        // Always use synthetic WindowInfo for control items on macOS 26+
        // because CGWindowListCreateDescriptionFromArray returns incorrect frame
        Self.logger.debug("Creating synthetic MenuBarItem for \(title) with frame \(frame)")
        self.window = WindowInfo.synthetic(
            windowID: windowID,
            frame: frame,
            title: title,
            ownerPID: ownerPID
        )
        self.info = info
    }
    
    /// Creates a menu bar item with a synthetic window and info.
    /// Used for macOS 26+ frame correction.
    init(syntheticWindow: WindowInfo, info: MenuBarItemInfo) {
        self.window = syntheticWindow
        self.info = info
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

        var titlePredicate: (MenuBarItem) -> Bool = { _ in true }
        var boundsPredicate: (CGWindowID) -> Bool = { _ in true }

        if onScreenOnly {
            option.insert(.onScreen)
        }
        if activeSpaceOnly {
            option.insert(.activeSpace)
            // Allow Ice's own items (control items) through even if title is empty
            titlePredicate = { $0.title != "" || $0.owningApplication == .current }
        }
        if let display {
            let displayBounds = CGDisplayBounds(display)
            boundsPredicate = { windowID in
                guard let windowFrame = Bridging.getWindowFrame(for: windowID) else {
                    return false
                }
                return displayBounds.intersects(windowFrame)
            }
        }

        let windowIDs = Bridging.getWindowList(option: option)
        let currentPID = ProcessInfo.processInfo.processIdentifier
        
        // Debug: check each windowID
        for windowID in windowIDs {
            if let window = WindowInfo(windowID: windowID), window.ownerPID == currentPID {
                logger.debug("Ice window in list: windowID=\(windowID), layer=\(window.layer), isMenuBarItem=\(window.isMenuBarItem), title=\(window.title ?? "nil")")
            }
        }
        
        return windowIDs.lazy
            .filter(boundsPredicate)
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

// MARK: MenuBarItemInfo Unchecked Item Window Initializer
private extension MenuBarItemInfo {
    private static let logger = Logger(category: "MenuBarItemInfo")
    
    /// Creates a simplified item from the given window.
    ///
    /// This initializer does not perform any checks on the window to ensure that
    /// it is a valid menu bar item window. Only call this initializer if you are
    /// certain that the window is valid.
    init(uncheckedItemWindow itemWindow: WindowInfo) {
        if let bundleIdentifier = itemWindow.owningApplication?.bundleIdentifier {
            self.namespace = Namespace(bundleIdentifier)
        } else {
            self.namespace = .null
        }
        if let title = itemWindow.title {
            // macOS 26 fix: Multiple control center items may have the same title (e.g., "Item-0")
            // Include windowID in title to make each item unique
            if title == "Item-0" || title.isEmpty {
                self.title = "\(title)#\(itemWindow.windowID)"
            } else {
                self.title = title
            }
        } else {
            self.title = "#\(itemWindow.windowID)"
        }
        
        // Debug: log items that might be Ice control items
        let ns = self.namespace.rawValue
        if ns.contains("Ice") || ns.contains("jordanbaird") {
            Self.logger.debug("Ice item created: namespace=\(ns), title='\(self.title)', ownerPID=\(itemWindow.ownerPID), windowTitle=\(itemWindow.title ?? "nil")")
        }
    }
}
