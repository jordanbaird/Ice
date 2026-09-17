//
//  MacOS27MenuBarItemProvider.swift
//  Ice
//
//  macOS 27 compatibility implementation derived from the GPLv3 Thaw project.
//

@preconcurrency import AXSwift
import Cocoa
import OSLog

/// Enumerates macOS 27 menu bar items through Accessibility.
///
/// macOS 27 no longer exposes each status item as an independent WindowServer
/// window. Every application still publishes its status items below
/// `AXExtrasMenuBar`, which also gives us direct process attribution.
@available(macOS 27.0, *)
enum MacOS27MenuBarItemProvider {
    private static let logger = Logger(category: "MacOS27MenuBarItemProvider")
    private static let maxItemHeight: CGFloat = 40
    /// Keep complete `AXExtrasMenuBar` walks from interleaving. Each owner's
    /// actual AX reads are also batched on the main thread below because
    /// HIServices' serializer is not safe when Ice answers an incoming AX
    /// hierarchy request at the same time as a background outgoing read.
    private static let operationLock = NSLock()
    // Accessed only inside main-thread AX batches, including targeted rereads.
    private static var runtimeIdentities = MacOS27RuntimeItemRegistry<AXUIElement>()

    private static let overflowControlLock = NSLock()
    private static var lastOverflowControlFrames = [CGRect]()

    /// The frames of MenuBarAgent's overflow button (the « button), from the
    /// most recent read that included MenuBarAgent.
    static var overflowControlFrames: [CGRect] {
        overflowControlLock.lock()
        defer { overflowControlLock.unlock() }
        return lastOverflowControlFrames
    }

    /// A single main-thread batch for our own controls only. Do not take the
    /// background scan lock here: its owner may be waiting for the main thread.
    @MainActor
    static func ownMenuBarItems() -> [MenuBarItem] {
        let frames = NSScreen.screens.map { screen in
            let display = CGDisplayBounds(screen.displayID)
            return CGRect(x: display.minX, y: display.minY, width: display.width, height: maxItemHeight)
        }
        let items = rawItems(
            from: .current,
            displayBounds: nil,
            menuBarFrames: frames,
            includeSupplementaryMetadata: false
        ).items
        for identifier in [ControlItem.Identifier.visible.rawValue, MenuBarItemTag.nativeBoundary(for: .hidden).title] {
            let matches = items.filter { $0.identityTitle == identifier }
            if let first = matches.first, matches.contains(where: { $0.bounds != first.bounds }) {
                return [] // Distinct hosted variants are not a settled pair.
            }
        }
        return assemble(items)
    }

    /// Performs an accessibility action on an item's element, which works
    /// while the item is concealed and not drawn in the menu bar.
    ///
    /// A right click prefers `AXShowMenu`; a left click prefers `AXPress`.
    /// Returns `false` if the element can't be found or has neither action.
    @MainActor
    static func pressItem(_ item: MenuBarItem, showingMenu: Bool) -> Bool {
        let frames = NSScreen.screens.map { screen in
            let display = CGDisplayBounds(screen.displayID)
            return CGRect(x: display.minX, y: display.minY, width: display.width, height: maxItemHeight)
        }
        var pids: Set<pid_t> = [item.ownerPID]
        if let sourcePID = item.sourcePID {
            pids.insert(sourcePID)
        }
        let owners = NSWorkspace.shared.runningApplications.filter { app in
            pids.contains(app.processIdentifier) || namespace(for: app) == item.tag.namespace
        }
        var candidates = [RawItem]()
        for owner in owners {
            let snapshot = rawItems(
                from: owner,
                displayBounds: nil,
                menuBarFrames: frames,
                includeSupplementaryMetadata: false,
                includingOffscreenItems: true
            )
            for rawItem in snapshot.items where rawItem.namespace == item.tag.namespace {
                if rawItem.identityTitle == item.tag.title {
                    candidates.append(rawItem)
                }
            }
        }
        candidates.sort { lhs, rhs in
            if lhs.bounds.minX == rhs.bounds.minX {
                return lhs.bounds.minY < rhs.bounds.minY
            }
            return lhs.bounds.minX < rhs.bounds.minX
        }
        let index = item.tag.instanceIndex
        guard let rawItem = candidates.indices.contains(index) ? candidates[index] : candidates.first else {
            logger.error("No accessibility element for \(item.logString, privacy: .public)")
            return false
        }

        let preferred: [Action] = showingMenu ? [.showMenu, .press] : [.press, .showMenu]
        for element in [rawItem.element] + AXHelpers.children(for: rawItem.element) {
            let actions = (try? element.actions()) ?? []
            guard let action = preferred.first(where: actions.contains) else {
                continue
            }
            // A press can open a menu that tracks before the owner replies.
            // Don't hold the main thread for that; the action is already sent.
            AXUIElementSetMessagingTimeout(element.element, 0.3)
            do {
                try element.performAction(action)
            } catch AXError.cannotComplete {
                // Timed out waiting for a reply, which a tracking menu causes.
            } catch {
                logger.error("\(action.rawValue, privacy: .public) on \(item.logString, privacy: .public) failed: \(error, privacy: .public)")
                continue
            }
            logger.notice("Performed \(action.rawValue, privacy: .public) on \(item.logString, privacy: .public) (actions: \(actions.map(\.rawValue), privacy: .public))")
            return true
        }
        logger.error("\(item.logString, privacy: .public) has no press or show-menu action")
        return false
    }

    /// Writes MenuBarAgent's own accessibility tree to the glyph debug log.
    ///
    /// Each app publishes its status items under its own `AXExtrasMenuBar`,
    /// but macOS 27 draws them from MenuBarAgent, and an app's frames go stale
    /// once macOS moves the item. This dump shows what MenuBarAgent reports.
    @MainActor
    static func dumpMenuBarAgentTree() {
        guard MacOS27GlyphDebug.isEnabled else { return }
        let agents = NSWorkspace.shared.runningApplications
            .filter { $0.bundleIdentifier == "com.apple.MenuBarAgent" }
        for agent in agents {
            guard let application = AXHelpers.application(for: agent) else { continue }
            let windows: [UIElement] = (try? application.arrayAttribute(.windows)) ?? []
            MacOS27GlyphDebug.log("Agent pid \(agent.processIdentifier): \(windows.count) windows")
            for (windowIndex, window) in windows.enumerated() {
                MacOS27GlyphDebug.log("  window \(windowIndex) frame=\(AXHelpers.frame(for: window)?.debugDescription ?? "none")")
                describe(window, depth: 2, limit: 3)
            }
        }
    }

    @MainActor
    private static func describe(_ element: UIElement, depth: Int, limit: Int) {
        guard depth <= limit + 1 else { return }
        for child in AXHelpers.children(for: element) {
            let role = AXHelpers.role(for: child)?.rawValue ?? "?"
            let identifier = AXHelpers.identifier(for: child) ?? "-"
            let description = AXHelpers.description(for: child) ?? AXHelpers.title(for: child) ?? "-"
            let frame = AXHelpers.frame(for: child)?.debugDescription ?? "none"
            let pid = AXHelpers.pid(for: child).map(String.init) ?? "-"
            MacOS27GlyphDebug.log(
                String(repeating: "  ", count: depth) + "\(role) id=\(identifier) desc=\(description) pid=\(pid) frame=\(frame)"
            )
            describe(child, depth: depth + 1, limit: limit)
        }
    }

    static func menuBarItems(
        on display: CGDirectDisplayID? = nil,
        option _: MenuBarItem.ListOption
    ) -> [MenuBarItem] {
        operationLock.lock()
        defer { operationLock.unlock() }

        guard AXHelpers.isProcessTrusted() else {
            logger.warning("Accessibility permission is missing; cannot enumerate macOS 27 menu bar items")
            return []
        }

        let displayBounds = display.map(CGDisplayBounds)
        return menuBarItems(
            from: NSWorkspace.shared.runningApplications,
            displayBounds: displayBounds,
            includeSupplementaryMetadata: true
        )
    }

    /// Reads only the owners involved in a reorder. A complete AX walk can
    /// spend the per-process timeout on every running app; two targeted owners
    /// are enough to refresh drag bounds and verify adjacency.
    static func menuBarItems(
        sourcePIDs: Set<pid_t>,
        namespaces: Set<MenuBarItemTag.Namespace> = []
    ) -> [MenuBarItem] {
        operationLock.lock()
        defer { operationLock.unlock() }

        guard
            AXHelpers.isProcessTrusted(),
            !sourcePIDs.isEmpty || !namespaces.isEmpty
        else {
            return []
        }

        // MenuBarAgent can terminate and relaunch hosted owners (notably
        // TextInputMenuAgent) during a native drag. Resolve each stable
        // namespace again as well as using the fast PID path, otherwise the
        // first post-drop snapshot can omit an item that is already visible
        // under its replacement process.
        var applicationsByPID = [pid_t: NSRunningApplication]()
        for sourcePID in sourcePIDs {
            guard let application = NSRunningApplication(processIdentifier: sourcePID) else {
                continue
            }
            applicationsByPID[sourcePID] = application
        }
        if !namespaces.isEmpty {
            for application in NSWorkspace.shared.runningApplications
            where namespaces.contains(namespace(for: application)) {
                applicationsByPID[application.processIdentifier] = application
            }
        }

        return menuBarItems(
            from: Array(applicationsByPID.values),
            displayBounds: nil,
            includeSupplementaryMetadata: false
        )
    }

    /// Live geometry for the status items macOS is drawing, read from
    /// MenuBarAgent's own accessibility tree.
    ///
    /// An app's `AXExtrasMenuBar` keeps reporting the frame an item had before
    /// macOS moved it, so items that are drawn again after leaving the
    /// overflow still look stacked there. MenuBarAgent draws the bar, and its
    /// per-item containers carry the positions it actually used.
    struct AgentGeometry {
        /// Container frames per owning process, ordered left to right.
        var framesByOwner = [pid_t: [CGRect]]()
        /// Frames of MenuBarAgent's overflow buttons.
        var overflowFrames = [CGRect]()
    }

    static func agentGeometry() -> AgentGeometry {
        var geometry = AgentGeometry()
        let agents = NSWorkspace.shared.runningApplications
            .filter { $0.bundleIdentifier == "com.apple.MenuBarAgent" }
        for agent in agents {
            guard let application = AXHelpers.application(for: agent) else { continue }
            let windows: [UIElement] = (try? application.arrayAttribute(.windows)) ?? []
            for window in windows {
                for child in AXHelpers.children(for: window) {
                    guard let frame = AXHelpers.frame(for: child) else { continue }
                    let childPID = AXHelpers.pid(for: child)
                    if AXHelpers.role(for: child) == .button, childPID == agent.processIdentifier {
                        // The overflow control sits beside the containers.
                        geometry.overflowFrames.append(frame)
                        continue
                    }
                    // The container nests the owning app's own element.
                    let owner = AXHelpers.children(for: child)
                        .compactMap { AXHelpers.pid(for: $0) }
                        .first { $0 != agent.processIdentifier } ?? childPID
                    guard let owner else { continue }
                    geometry.framesByOwner[owner, default: []].append(frame)
                }
            }
        }
        for (owner, frames) in geometry.framesByOwner {
            geometry.framesByOwner[owner] = frames.sorted { $0.minX < $1.minX }
        }
        return geometry
    }

    /// Replaces each item's frame with the one MenuBarAgent drew it at, and
    /// marks the items it isn't drawing at all.
    private static func applyingAgentGeometry(to items: [MenuBarItem]) -> [MenuBarItem] {
        let geometry = agentGeometry()
        guard !geometry.framesByOwner.isEmpty else { return items }

        // Match an owner's items to its containers left to right.
        var nextIndexByOwner = [pid_t: Int]()
        var frameByTag = [MenuBarItemTag: CGRect]()
        for item in items.sorted(by: { $0.bounds.minX < $1.bounds.minX }) {
            let owner = item.sourcePID ?? item.ownerPID
            guard let frames = geometry.framesByOwner[owner] else { continue }
            let index = nextIndexByOwner[owner, default: 0]
            guard frames.indices.contains(index) else { continue }
            nextIndexByOwner[owner] = index + 1
            frameByTag[item.tag] = frames[index]
        }
        let allFrames = Array(frameByTag.values)

        return items.map { item in
            guard let frame = frameByTag[item.tag] else { return item }
            let overlapsOverflow = geometry.overflowFrames.contains { $0.intersects(frame) }
            let overlapsOther = allFrames.contains { other in
                other != frame && other.intersection(frame).width > 6
            }
            // Containers are the full height of the menu bar; keep the item's
            // own height, which is what a capture should crop.
            let height = min(frame.height, max(item.bounds.height, 22))
            return MenuBarItem(
                tag: item.tag,
                windowID: item.windowID,
                ownerPID: item.ownerPID,
                sourcePID: item.sourcePID,
                bounds: CGRect(
                    x: frame.minX,
                    y: frame.midY - height / 2,
                    width: frame.width,
                    height: height
                ),
                title: item.title,
                accessibilityHelp: item.accessibilityHelp,
                accessibilityValue: item.accessibilityValue,
                isOnScreen: !overlapsOverflow && !overlapsOther
            )
        }
    }

    private static func menuBarItems(
        from runningApplications: [NSRunningApplication],
        displayBounds: CGRect?,
        includeSupplementaryMetadata: Bool
    ) -> [MenuBarItem] {
        var rawItems = [RawItem]()
        let menuBarFrames = AXHelpers.performOnMain {
            runtimeIdentities.removeUnavailableOwners(
                Set(NSWorkspace.shared.runningApplications.map(runtimeOwner))
            )
            return NSScreen.screens.map { screen in
                let display = CGDisplayBounds(screen.displayID)
                return CGRect(x: display.minX, y: display.minY, width: display.width, height: maxItemHeight)
            }
        }

        for runningApp in runningApplications {
            rawItems.append(contentsOf: AXHelpers.performOnMain {
                Self.rawItems(
                    from: runningApp,
                    displayBounds: displayBounds,
                    menuBarFrames: menuBarFrames,
                    includeSupplementaryMetadata: includeSupplementaryMetadata
                ).items
            })
        }

        let assembled = assemble(rawItems)
        return AXHelpers.performOnMain { applyingAgentGeometry(to: assembled) }
    }

    /// A grace-period expiry is not enough to remove a retained tile: confirm
    /// its owner still answers AX and no longer publishes that identity. Do
    /// not take operationLock on main; a background scan may be waiting on us.
    @MainActor
    static func confirmedAbsentIdentifiers(for items: [MenuBarItem]) -> Set<String> {
        let frames = NSScreen.screens.map { screen in
            let display = CGDisplayBounds(screen.displayID)
            return CGRect(x: display.minX, y: display.minY, width: display.width, height: maxItemHeight)
        }
        var absent = Set<String>()
        let applications = NSWorkspace.shared.runningApplications
        for (itemNamespace, candidates) in Dictionary(grouping: items, by: { $0.tag.namespace }) {
            let owners = applications.filter { namespace(for: $0) == itemNamespace }
            guard !owners.isEmpty else { continue }
            let snapshots = owners.map {
                rawItems(
                    from: $0,
                    displayBounds: nil,
                    menuBarFrames: frames,
                    includeSupplementaryMetadata: false,
                    includingOffscreenItems: true
                )
            }
            guard snapshots.allSatisfy(\.isComplete) else { continue }
            // Raw identities include ambiguous hosted variants. Their geometry
            // is not usable for a move, but they still prove the item exists.
            let identities = Set(snapshots.flatMap(\.items).map { "\($0.namespace):\($0.identityTitle)" })
            absent.formUnion(candidates.filter {
                !identities.contains("\($0.tag.namespace):\($0.tag.title)")
            }.map { $0.tag.persistentIdentifier })
        }
        return absent
    }

    private struct RawSnapshot {
        var items = [RawItem]()
        var isComplete = true
    }

    private static func rawItems(
        from runningApp: NSRunningApplication,
        displayBounds: CGRect?,
        menuBarFrames: [CGRect],
        includeSupplementaryMetadata: Bool,
        includingOffscreenItems: Bool = false
    ) -> RawSnapshot {
        precondition(Thread.isMainThread)
        guard let application = AXHelpers.application(for: runningApp) else {
            return RawSnapshot(isComplete: false)
        }
        let children: [UIElement]
        do {
            guard let extras: UIElement = try application.attribute(.extrasMenuBar) else {
                return RawSnapshot() // A successful read can report no status items.
            }
            children = try extras.arrayAttribute(.children) ?? []
        } catch let error as AXError where error == .notImplemented {
            // Some hosts remove AXExtrasMenuBar along with their final item.
            // Only a successful attribute-list read that omits it establishes
            // absence; a timeout/unresponsive owner is never treated as empty.
            if let attributes = try? application.attributes(), !attributes.contains(.extrasMenuBar) {
                return RawSnapshot()
            }
            return RawSnapshot(isComplete: false)
        } catch {
            return RawSnapshot(isComplete: false)
        }

        let namespace = namespace(for: runningApp)
        var fallbackIndex = 0
        var result = RawSnapshot()
        for (childIndex, child) in children.enumerated() {
            guard let frame = AXHelpers.frame(for: child) else {
                result.isComplete = false
                continue
            }
            guard MacOS27ItemSnapshotGeometry.includes(
                frame: frame,
                menuBarFrames: menuBarFrames,
                maxItemHeight: maxItemHeight,
                includingOffscreenItems: includingOffscreenItems
            ) else {
                continue
            }

            if let displayBounds, !displayBounds.contains(CGPoint(x: frame.midX, y: frame.midY)) {
                continue
            }

            var identityDescendants: [UIElement]?
            let identifier: String?
            do {
                if let ownIdentifier = nonEmpty(try child.attribute(.identifier)) {
                    identifier = ownIdentifier
                } else {
                    let descendants: [UIElement] = try child.arrayAttribute(.children) ?? []
                    identityDescendants = descendants
                    var descendantIdentifier: String?
                    for descendant in descendants {
                        if let value = nonEmpty(try descendant.attribute(.identifier)) {
                            descendantIdentifier = value
                            break
                        }
                    }
                    identifier = descendantIdentifier
                }
            } catch {
                // A failed metadata read is not evidence that the element
                // lacks an identifier. Never mint a fallback identity for it.
                result.isComplete = false
                continue
            }
            lazy var descendants = identityDescendants ?? AXHelpers.children(for: child)
            let accessibilityDescription = nonEmpty(AXHelpers.description(for: child))
                ?? descendants.compactMap { nonEmpty(AXHelpers.description(for: $0)) }.first
            let accessibilityHelp = includeSupplementaryMetadata
                ? nonEmpty(AXHelpers.help(for: child))
                    ?? descendants.compactMap { nonEmpty(AXHelpers.help(for: $0)) }.first
                : nil
            let accessibilityValue = includeSupplementaryMetadata
                ? nonEmpty(AXHelpers.value(for: child))
                    ?? descendants.compactMap { nonEmpty(AXHelpers.value(for: $0)) }.first
                : nil
            let accessibilityTitle = nonEmpty(AXHelpers.title(for: child))
            let fallbackTitle = "Item-\(fallbackIndex)"
            let displayTitle = accessibilityTitle ?? accessibilityDescription ?? identifier ?? fallbackTitle
            if accessibilityTitle == nil, accessibilityDescription == nil, identifier == nil {
                fallbackIndex += 1
            }

            // TextInputMenuAgent exposes the currently selected input source
            // (for example "ABC" or "简体拼音") as its AX description. That
            // label is presentation, not identity.
            let identityTitle = if namespace == .textInputMenuAgent {
                "Item-\(childIndex)"
            } else if
                identifier == nil,
                runningApp.bundleIdentifier != Constants.bundleIdentifier,
                runningApp.bundleIdentifier?.hasPrefix("com.apple.") != true
            {
                runtimeIdentities.identity(
                    for: child.element,
                    owner: runtimeOwner(runningApp),
                    now: ProcessInfo.processInfo.systemUptime,
                    equals: { CFEqual($0, $1) }
                )
            } else {
                identifier ?? accessibilityDescription ?? displayTitle
            }
            let ownerPID = AXHelpers.pid(for: child) ?? runningApp.processIdentifier
            result.items.append(
                RawItem(
                    namespace: namespace,
                    identityTitle: identityTitle,
                    displayTitle: displayTitle,
                    bounds: frame,
                    ownerPID: ownerPID,
                    accessibilityHelp: accessibilityHelp,
                    accessibilityValue: accessibilityValue,
                    element: child
                )
            )
        }
        return result
    }

    private struct RawItem {
        let namespace: MenuBarItemTag.Namespace
        let identityTitle: String
        let displayTitle: String
        let bounds: CGRect
        let ownerPID: pid_t
        let accessibilityHelp: String?
        let accessibilityValue: String?
        let element: UIElement
    }

    private static func assemble(_ rawItems: [RawItem]) -> [MenuBarItem] {
        let sorted = rawItems.sorted { lhs, rhs in
            if lhs.bounds.minX == rhs.bounds.minX {
                return lhs.bounds.minY < rhs.bounds.minY
            }
            return lhs.bounds.minX < rhs.bounds.minX
        }
        var seenIceControlItems = Set<String>()
        var seenRuntimeItems = Set<String>()
        var nextIndexByIdentity = [String: Int]()
        let ambiguousRuntimeItems = Set(Dictionary(grouping: rawItems, by: \.identityTitle).compactMap { title, items in
            guard
                title.hasPrefix(MacOS27RuntimeItemIdentity.prefix),
                let first = items.first,
                items.contains(where: { $0.bounds != first.bounds })
            else {
                return nil as String?
            }
            return title
        })

        // Items in MenuBarAgent's overflow aren't drawn in the menu bar. They
        // report stale frames stacked on the overflow button, so a frame that
        // overlaps the button or another item doesn't describe a drawn item.
        let overflowControls = rawItems.filter(isNativeOverflowControl)
        let overflowFrames: [CGRect]
        if rawItems.contains(where: { $0.namespace == .controlCenter }) {
            overflowFrames = overflowControls.map(\.bounds)
            overflowControlLock.lock()
            lastOverflowControlFrames = overflowFrames
            overflowControlLock.unlock()
        } else {
            overflowFrames = overflowControlFrames
        }
        let contentItems = rawItems.filter { !isNativeOverflowControl($0) }
        func isDrawn(_ rawItem: RawItem) -> Bool {
            if overflowFrames.contains(where: { $0.intersects(rawItem.bounds) }) {
                return false
            }
            // Hosted hit areas of adjacent items can overlap by a few points.
            return !contentItems.contains { other in
                guard other.identityTitle != rawItem.identityTitle || other.namespace != rawItem.namespace else {
                    return false
                }
                return rawItem.bounds.intersection(other.bounds).width > 6
            }
        }

        return sorted.compactMap { rawItem in
            guard !isNativeOverflowControl(rawItem) else {
                return nil
            }
            if rawItem.identityTitle.hasPrefix(MacOS27RuntimeItemIdentity.prefix) {
                guard
                    !ambiguousRuntimeItems.contains(rawItem.identityTitle),
                    seenRuntimeItems.insert(rawItem.identityTitle).inserted
                else {
                    return nil
                }
            }

            // AppKit publishes both the primary scene and a presentation
            // variant for Ice's NSStatusItems on macOS 27. They have the same
            // accessibility identifier and represent one logical button. Ice
            // control identifiers are unique, so retain only one variant.
            if
                rawItem.namespace == .ice,
                ControlItem.Identifier(rawValue: rawItem.identityTitle) != nil,
                !seenIceControlItems.insert(rawItem.identityTitle).inserted
            {
                return nil
            }

            let identity = "\(rawItem.namespace):\(rawItem.identityTitle)"
            let instanceIndex = nextIndexByIdentity[identity, default: 0]
            nextIndexByIdentity[identity] = instanceIndex + 1
            let windowID = syntheticWindowID(identity: identity, instanceIndex: instanceIndex)
            let tag = MenuBarItemTag(
                namespace: rawItem.namespace,
                title: rawItem.identityTitle,
                instanceIndex: instanceIndex
            )
            return MenuBarItem(
                tag: tag,
                windowID: windowID,
                ownerPID: rawItem.ownerPID,
                sourcePID: rawItem.ownerPID,
                bounds: rawItem.bounds,
                title: rawItem.displayTitle,
                accessibilityHelp: rawItem.accessibilityHelp,
                accessibilityValue: rawItem.accessibilityValue,
                isOnScreen: isDrawn(rawItem)
            )
        }
    }

    private static func namespace(for app: NSRunningApplication) -> MenuBarItemTag.Namespace {
        switch app.bundleIdentifier {
        case "com.apple.MenuBarAgent":
            // Preserve Ice's existing Control Center item identities.
            return .controlCenter
        case Constants.bundleIdentifier:
            return .ice
        case let bundleIdentifier?:
            return .string(bundleIdentifier)
        case nil:
            return .optional(app.localizedName)
        }
    }

    private static func runtimeOwner(_ app: NSRunningApplication) -> String {
        "\(app.processIdentifier):\(app.launchDate?.timeIntervalSinceReferenceDate ?? 0)"
    }

    private static func nonEmpty(_ string: String?) -> String? {
        guard let string else { return nil }
        let trimmed = string.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    /// Returns whether a raw item is MenuBarAgent's overflow button. It has no
    /// `com.apple.menuextra` identifier, only a localized description such as
    /// "Show Hidden Menu Bar Items".
    private static func isNativeOverflowControl(_ rawItem: RawItem) -> Bool {
        if rawItem.namespace == .controlCenter, !rawItem.identityTitle.hasPrefix("com.apple.") {
            return true
        }
        let normalized = rawItem.identityTitle.lowercased()
        return normalized.contains("overflow") || normalized.contains("chevron")
    }

    private static func syntheticWindowID(identity: String, instanceIndex: Int) -> CGWindowID {
        var hash: UInt32 = 0x811C_9DC5
        for byte in "\(identity):\(instanceIndex)".utf8 {
            hash ^= UInt32(byte)
            hash = hash &* 0x0100_0193
        }
        return CGWindowID(0x8000_0000 | (hash & 0x7FFF_FFFF))
    }
}
