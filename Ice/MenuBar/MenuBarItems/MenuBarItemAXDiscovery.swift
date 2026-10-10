//
//  MenuBarItemAXDiscovery.swift
//  Ice
//

import ApplicationServices
import Carbon.HIToolbox
import Cocoa
import OSLog

/// Lists menu bar items via Accessibility (`AXExtrasMenuBar`).
///
/// This only needs Accessibility permission, not Screen Recording,
/// and still works when `CGSGetProcessMenuBarWindowList` no longer returns
/// per-item windows (macOS 27+) — the same approach Thaw uses.
enum MenuBarItemAXDiscovery {
    /// A menu bar item read via Accessibility.
    struct AXMenuBarItem: Hashable {
        /// Exact click target; identifiers and titles can be missing or shared by siblings.
        let element: AXUIElement

        /// Process identifier of the app owning the item. Used to fetch the app icon.
        let pid: pid_t

        /// Display name of the app owning the item.
        let appName: String

        /// Bundle identifier of the app owning the item.
        let bundleID: String?

        /// `AXIdentifier` of the item (e.g. `com.apple.menuextra.wifi`).
        let identifier: String?

        /// Title/description of the item (may be nil for icon-only items).
        let title: String?

        /// Raw frame of the item in AX coordinates (top-left origin).
        /// Convert to Cocoa coordinates when classifying.
        let axFrame: CGRect?

        /// Most descriptive name for display.
        var displayName: String {
            title ?? identifier ?? appName
        }
    }

    /// The menubar group an item currently belongs to.
    enum SectionKind: Hashable {
        case visible
        case hidden
        case alwaysHidden
    }

    /// Classifies an item by its horizontal position relative to Ice's dividers.
    ///
    /// The X axis is identical in both AX and Cocoa coordinates (only the Y axis is flipped),
    /// so this works for both AX frames and CGS window frames.
    ///
    /// Each divider is evaluated independently so this stays correct when a section is disabled
    /// (its divider is nil): left of the Always-Hidden divider → alwaysHidden,
    /// left of the Hidden divider → hidden, otherwise → visible.
    ///
    /// - Parameters:
    ///   - centerX: X center of the item, nil when unreadable (falls back to Visible).
    ///   - hiddenDividerX: Left edge (minX) of the Hidden divider, nil when the section is disabled.
    ///   - alwaysHiddenDividerX: Left edge of the Always Hidden divider, nil when the section is disabled.
    static func classify(
        centerX: CGFloat?,
        hiddenDividerX: CGFloat?,
        alwaysHiddenDividerX: CGFloat?
    ) -> SectionKind {
        guard let centerX else {
            return .visible
        }
        let dividers = normalizedDividers(
            hiddenDividerX: hiddenDividerX,
            alwaysHiddenDividerX: alwaysHiddenDividerX
        )
        if let alwaysHiddenX = dividers.alwaysHidden, centerX < alwaysHiddenX {
            return .alwaysHidden
        }
        if let hiddenX = dividers.hidden, centerX < hiddenX {
            return .hidden
        }
        return .visible
    }

    /// Normalizes invalid swapped divider geometry for every section-boundary use.
    ///
    /// macOS 27 can leave the Always-Hidden divider right of the Hidden divider.
    /// Ignoring only that boundary for classification while using it for drop
    /// bounds would still target the wrong section.
    static func normalizedDividers(
        hiddenDividerX: CGFloat?,
        alwaysHiddenDividerX: CGFloat?
    ) -> (hidden: CGFloat?, alwaysHidden: CGFloat?) {
        if
            let alwaysHiddenDividerX,
            let hiddenDividerX,
            alwaysHiddenDividerX > hiddenDividerX
        {
            return (hiddenDividerX, nil)
        }
        return (hiddenDividerX, alwaysHiddenDividerX)
    }

    /// Returns true when the app has been granted Accessibility permission.
    static func isTrusted() -> Bool {
        AXIsProcessTrusted()
    }

    /// Icon of the current input source (the keyboard/layout indicator on the menubar).
    ///
    /// Used for the TextInputMenuAgent item — that app has no icon of its own,
    /// the real icon on the menubar is the current input source's icon.
    static func inputSourceIcon() -> NSImage? {
        let source = TISCopyCurrentKeyboardInputSource().takeRetainedValue()
        guard let pointer = TISGetInputSourceProperty(source, kTISPropertyIconImageURL) else {
            return nil
        }
        let url = Unmanaged<CFURL>.fromOpaque(pointer).takeUnretainedValue() as URL
        return NSImage(contentsOf: url)
    }

    /// SF Symbol for familiar system menu extras.
    ///
    /// These items are usually hosted by MenuBarAgent, so resolving the app icon by
    /// PID yields a generic, incorrect icon.
    static func systemImageName(forIdentifier identifier: String?) -> String? {
        switch identifier {
        case "com.apple.menuextra.wifi": "wifi"
        case "com.apple.menuextra.sound": "speaker.wave.2.fill"
        case "com.apple.menuextra.bluetooth": "bluetooth"
        case "com.apple.menuextra.battery": "battery.100"
        case "com.apple.menuextra.controlcenter": "switch.2"
        case "com.apple.menuextra.clock": "clock"
        case "com.apple.menuextra.spotlight": "magnifyingglass"
        case "com.apple.menuextra.airplay": "airplayvideo"
        default: nil
        }
    }

    /// SF Symbol for a CGS menu bar item (no AX identifier available).
    ///
    /// Same intent as `systemImageName(forIdentifier:)`: ControlCenter /
    /// SystemUIServer extras share one host app, so `owningApplication.icon`
    /// is the same generic icon for Sound, Wi-Fi, Clock… — mapping the
    /// title keeps Visible stable across CGS/AX sources instead of
    /// flickering between a generic icon and an SF Symbol per refresh.
    /// Only applies to `com.apple.*` hosts so third-party apps keep
    /// their real icons.
    static func systemImageName(forTitle title: String?, bundleID: String?) -> String? {
        guard bundleID?.hasPrefix("com.apple.") == true else {
            return nil
        }
        switch title?.lowercased() ?? "" {
        case "wifi", "wi-fi": return "wifi"
        case "sound": return "speaker.wave.2.fill"
        case "bluetooth": return "bluetooth"
        case "battery", "batterymenu": return "battery.100"
        case "bentobox", "controlcenter", "control center": return "switch.2"
        case "clock": return "clock"
        case "spotlight": return "magnifyingglass"
        case "airplay", "screenmirroring", "screen mirroring": return "airplayvideo"
        default: return nil
        }
    }

    /// Lists all menu bar items of running apps.
    ///
    /// - Parameter apps: The apps to scan. Pass `NSWorkspace.shared.runningApplications`
    ///   from the main thread.
    /// - Returns: The item list, sorted by display name.
    static func discoverItems(in apps: [NSRunningApplication]) -> [AXMenuBarItem] {
        guard isTrusted() else {
            return []
        }
        // Drops Ice's own icons (the dividers) from the list.
        let ownBundleID = Bundle.main.bundleIdentifier
        var result = [AXMenuBarItem]()
        var visited = 0
        for app in apps {
            guard visited < maxElementsVisited else {
                break
            }
            guard app.bundleIdentifier != ownBundleID else {
                continue
            }
            result.append(contentsOf: items(for: app, visited: &visited))
        }
        return result.sorted {
            $0.displayName.localizedCaseInsensitiveCompare($1.displayName) == .orderedAscending
        }
    }

    /// Presses (AXPress) the exact menu bar item retained during discovery.
    ///
    /// Used for the Ice Bar on macOS 27: with no CGS window left for temp-show +
    /// click, press directly via Accessibility and let the system open the menu.
    /// AXPress does not distinguish left/right — most extras ignore right-click,
    /// so the Ice Bar shares one action for both. Runs in the background (each app may
    /// block up to ~1s per the messaging timeout); returns true once pressed.
    ///
    /// If the element has become invalid, fail without pressing another item from its app.
    static func press(_ item: AXMenuBarItem) -> Bool {
        guard isTrusted() else {
            return false
        }
        AXUIElementSetMessagingTimeout(item.element, 1)
        let currentFrame = frame(of: item.element)
        os.Logger(subsystem: "com.jordanbaird.Ice", category: "AXDiscovery")
            .info("axPress geometry pid=\(item.pid) original=\(String(describing: item.axFrame), privacy: .public) current=\(String(describing: currentFrame), privacy: .public)")
        let result = AXUIElementPerformAction(item.element, kAXPressAction as CFString)
        os.Logger(subsystem: "com.jordanbaird.Ice", category: "AXDiscovery")
            .info("axPress result pid=\(item.pid) element=\(CFHash(item.element)) code=\(result.rawValue)")
        return result == .success
    }

    /// Frames (in AX coordinates, same system as `AXMenuBarItem.axFrame`) of Ice's
    /// dividers, looked up via Accessibility.
    ///
    /// On macOS 27 `NSStatusItem.button.window.frame` returns the spacer's rect
    /// rather than the chevron position, so the Ice Bar cannot use it to classify
    /// sections. Dividers are identified by the `accessibilityIdentifier` set by
    /// ControlItem itself, so this lookup is exact and independent of window
    /// layout. It only reads our own app, so it is fast and safe to call in the background.
    ///
    /// - Note: When the spacer is expanded (section hidden), the divider's window is parked
    ///   offscreen and the returned frame is a junk rect (hundreds of pt wide, below
    ///   the bottom of the screen). Always filter via ``isSettledDividerFrame(_:)`` before
    ///   using `minX` for classification.
    static func dividerFrames() -> (hidden: CGRect?, alwaysHidden: CGRect?) {
        guard isTrusted() else {
            return (nil, nil)
        }
        let axApp = AXUIElementCreateApplication(NSRunningApplication.current.processIdentifier)
        AXUIElementSetMessagingTimeout(axApp, 1)

        var bar: AnyObject?
        guard
            AXUIElementCopyAttributeValue(axApp, "AXExtrasMenuBar" as CFString, &bar) == .success,
            let bar,
            CFGetTypeID(bar) == AXUIElementGetTypeID()
        else {
            return (nil, nil)
        }
        // swiftlint:disable:next force_cast
        let barElement = bar as! AXUIElement
        var visited = 0
        var found = [String: CGRect]()
        collectDividerFrames(from: barElement, depth: maxWalkDepth, visited: &visited, into: &found)
        return (found["IceHiddenDivider"], found["IceAlwaysHiddenDivider"])
    }

    /// Whether an AX frame looks like a real divider in the menubar.
    ///
    /// An expanded spacer (hidden section) yields a WIDE frame (hundreds of pt), but minX still
    /// matches the chevron position and minY still falls within the menubar band — keep it to read
    /// minX for classification. Only discards junk frames parked offscreen (minY below the
    /// screen bottom, e.g. 986) or minX stuck at the left edge.
    static func isSettledDividerFrame(_ frame: CGRect) -> Bool {
        frame.minY <= 100 && frame.minX > 100
    }

    /// Collects frames of elements carrying Ice's `accessibilityIdentifier`.
    ///
    /// Mirrors `collectItems` (skips the `AXMenu`/`AXMenuItem` tree, descends at most
    /// `maxWalkDepth`), but records frames by identifier instead of building items.
    /// The identifier may live on the wrapper element or the inner button — takes the
    /// first frame found for each identifier.
    private static func collectDividerFrames(
        from element: AXUIElement,
        depth: Int,
        visited: inout Int,
        into result: inout [String: CGRect]
    ) {
        guard depth > 0, visited < maxElementsVisited else {
            return
        }
        visited += 1

        let role = stringAttribute(kAXRoleAttribute as CFString, of: element)

        guard role != "AXMenu", role != "AXMenuItem" else {
            return
        }

        if
            let identifier = stringAttribute("AXIdentifier" as CFString, of: element),
            identifier == "IceHiddenDivider" || identifier == "IceAlwaysHiddenDivider",
            result[identifier] == nil,
            let frame = frame(of: element)
        {
            result[identifier] = frame
        }

        var children: AnyObject?
        guard
            AXUIElementCopyAttributeValue(element, kAXChildrenAttribute as CFString, &children) == .success,
            let elements = children as? [AXUIElement]
        else {
            return
        }
        for child in elements {
            collectDividerFrames(from: child, depth: depth - 1, visited: &visited, into: &result)
        }
    }

    /// Maximum number of elements read in a single scan.
    private static let maxElementsVisited = 256

    /// Maximum depth when descending the AX tree.
    ///
    /// Real items usually sit at grandchild level (e.g. `AXGroup` → `AXMenuBarItem`
    /// inside MenuBarAgent), so this must descend instead of only reading direct
    /// children of `AXExtrasMenuBar`.
    private static let maxWalkDepth = 4

    /// Reads an app's `AXExtrasMenuBar`.
    private static func items(for app: NSRunningApplication, visited: inout Int) -> [AXMenuBarItem] {
        let axApp = AXUIElementCreateApplication(app.processIdentifier)
        // ponytail: short timeout per app — one hung app must not block the whole scan (the system default waits up to 6s).
        AXUIElementSetMessagingTimeout(axApp, 1)

        var bar: AnyObject?
        guard
            AXUIElementCopyAttributeValue(axApp, "AXExtrasMenuBar" as CFString, &bar) == .success,
            let bar,
            CFGetTypeID(bar) == AXUIElementGetTypeID()
        else {
            return []
        }
        // swiftlint:disable:next force_cast
        let barElement = bar as! AXUIElement

        let appName = app.localizedName ?? app.bundleIdentifier ?? "Unknown"
        var result = [AXMenuBarItem]()
        collectItems(
            from: barElement,
            pid: app.processIdentifier,
            appName: appName,
            bundleID: app.bundleIdentifier,
            depth: maxWalkDepth,
            visited: &visited,
            into: &result
        )
        return result
    }

    /// Collects items from an AX element.
    ///
    /// - `AXMenu`/`AXMenuItem` is dropdown content; skip the whole tree.
    /// - `AXMenuBarItem` is a real icon; record it immediately without descending.
    /// - Everything else (wrapper groups…) descends first; only records the outer
    ///   element when nothing inside is an item.
    private static func collectItems(
        from element: AXUIElement,
        pid: pid_t,
        appName: String,
        bundleID: String?,
        depth: Int,
        visited: inout Int,
        into result: inout [AXMenuBarItem]
    ) {
        guard depth > 0, visited < maxElementsVisited else {
            return
        }
        visited += 1

        let role = stringAttribute(kAXRoleAttribute as CFString, of: element)

        guard role != "AXMenu", role != "AXMenuItem" else {
            return
        }

        if role == "AXMenuBarItem" {
            record(element, pid: pid, appName: appName, bundleID: bundleID, into: &result, recordNameless: true)
            return
        }

        var children: AnyObject?
        if
            AXUIElementCopyAttributeValue(element, kAXChildrenAttribute as CFString, &children) == .success,
            let elements = children as? [AXUIElement],
            !elements.isEmpty
        {
            let countBefore = result.count
            for child in elements {
                collectItems(from: child, pid: pid, appName: appName, bundleID: bundleID, depth: depth - 1, visited: &visited, into: &result)
            }
            // When a child is an item, skip the wrapper element.
            guard result.count == countBefore else {
                return
            }
        }

        record(element, pid: pid, appName: appName, bundleID: bundleID, into: &result, recordNameless: false)
    }

    /// Records an element as an item when it has an identity.
    private static func record(
        _ element: AXUIElement,
        pid: pid_t,
        appName: String,
        bundleID: String?,
        into result: inout [AXMenuBarItem],
        recordNameless: Bool
    ) {
        let identifier = stringAttribute("AXIdentifier" as CFString, of: element)
        let title = stringAttribute(kAXTitleAttribute as CFString, of: element)
            ?? stringAttribute(kAXDescriptionAttribute as CFString, of: element)
            ?? stringAttribute(kAXHelpAttribute as CFString, of: element)

        guard identifier != nil || title != nil || recordNameless else {
            return
        }
        result.append(
            AXMenuBarItem(
                element: element,
                pid: pid,
                appName: appName,
                bundleID: bundleID,
                identifier: identifier,
                title: title,
                axFrame: frame(of: element)
            )
        )
    }

    /// Reads an element's raw frame (AX coordinates), nil when absent.
    private static func frame(of element: AXUIElement) -> CGRect? {
        var position: AnyObject?
        var size: AnyObject?
        guard
            AXUIElementCopyAttributeValue(element, kAXPositionAttribute as CFString, &position) == .success,
            AXUIElementCopyAttributeValue(element, kAXSizeAttribute as CFString, &size) == .success,
            let position, let size,
            CFGetTypeID(position) == AXValueGetTypeID(),
            CFGetTypeID(size) == AXValueGetTypeID()
        else {
            return nil
        }
        // swiftlint:disable:next force_cast
        let positionValue = position as! AXValue
        // swiftlint:disable:next force_cast
        let sizeValue = size as! AXValue
        var point = CGPoint.zero
        var cgSize = CGSize.zero
        guard
            AXValueGetValue(positionValue, .cgPoint, &point),
            AXValueGetValue(sizeValue, .cgSize, &cgSize)
        else {
            return nil
        }
        return CGRect(origin: point, size: cgSize)
    }

    /// Reads a string attribute of an AX element, nil when missing/on error.
    private static func stringAttribute(_ attribute: CFString, of element: AXUIElement) -> String? {
        var value: AnyObject?
        guard AXUIElementCopyAttributeValue(element, attribute, &value) == .success,
              let string = value as? String,
              !string.isEmpty
        else {
            return nil
        }
        return string
    }
}
