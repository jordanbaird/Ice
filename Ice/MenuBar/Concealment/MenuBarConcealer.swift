//
//  MenuBarConcealer.swift
//  Ice
//
//  The assessment-mode assertion and the click bridge are adapted from
//  Ice PR #995 and HiBar (https://github.com/3dot141/HiBar), which adapted
//  them from Barometer (https://github.com/mackid1993/Barometer) and Thaw's
//  PlatformRuntimeKit (https://github.com/thaw-app/Thaw). All are licensed
//  under the GNU GPLv3, like Ice.
//

import Cocoa
import Combine

// MARK: - MenuBarConcealer

/// Hides sections on macOS 27 while a display without a notch is attached.
///
/// Ice's spacer only hides on a display that moves its own overflow out of
/// sight, which a notched laptop on its own does. With a display without a
/// notch attached it breaks down: the spacer fits there, or squeezes the
/// active app's menus instead of overflowing, and the display Accessibility
/// reports follows the user's focus, so the spacer can't be placed reliably
/// (issues #12, #17, #24). In that case whole applications are hidden through
/// MenuBarAgent's assessment mode instead, on every display at once.
///
/// Trade-offs, measured on macOS 27.2 (and on 27.0 in Ice PR #995):
/// - Hiding works per application: an app is hidden when none of its items
///   sits in the visible section.
/// - While anything is hidden, the bar also drops the items of apps that are
///   not Developer ID-signed (Ice itself when built ad-hoc) and a few system
///   items such as Focus and Control Center controls.
/// - MenuBarAgent ignores clicks on its own items (clock, Wi-Fi, battery…)
///   while anything is hidden. Such a click is held back, hiding is lifted
///   for a moment, and the click is replayed.
@MainActor
final class MenuBarConcealer {
    /// How much of the hidden content is revealed.
    private enum RevealState {
        case allHidden
        case hiddenRevealed
        case allRevealed
    }

    /// Defaults key of the learned section of each application.
    private static let sectionsKey = "MacOS27AppSections"

    /// Defaults key that forces a backend: "spacer" or "assessment".
    private static let modeOverrideKey = "MacOS27HidingMode"

    /// Applications that are never hidden: Ice itself (so it can always bring
    /// the others back) and the processes behind the system items.
    private static let neverHidden: Set<String> = [
        Bundle.main.bundleIdentifier ?? "com.jordanbaird.Ice",
        "com.apple.MenuBarAgent",
        "com.apple.controlcenter",
        "com.apple.systemuiserver",
        "com.apple.notificationcenterui",
        "com.apple.Spotlight",
    ]

    private weak var appState: AppState?
    private var cancellables = Set<AnyCancellable>()

    /// The live assertion and the applications it hides.
    private var live: (token: AnyObject, concealed: Set<String>, allowed: [String])?

    /// The update that is running; updates run one after another.
    private var applyTask: Task<Void, Never>?

    /// Counts updates, so one overtaken by a later one is skipped.
    private var updateGeneration = 0

    /// Hiding stays lifted until then, so a replayed click reaches a system item.
    private var suspendedUntil: ContinuousClock.Instant?

    /// Whether the last update ran with this backend in use.
    private var wasInUse = false

    /// Whether anything is hidden right now.
    var isConcealing: Bool {
        live != nil
    }

    /// Whether sections are hidden by the concealer rather than by spacers.
    static var isInUse: Bool {
        guard #available(macOS 27, *), AssessmentAssertion.isAvailable else {
            return false
        }
        switch UserDefaults.standard.string(forKey: modeOverrideKey) {
        case "spacer": return false
        case "assessment": return true
        default: return NSScreen.screens.contains { !$0.hasNotch }
        }
    }

    // MARK: Setup

    /// Starts following the sections' states.
    func performSetup(with appState: AppState) {
        self.appState = appState
        guard #available(macOS 27, *), AssessmentAssertion.isAvailable else {
            return
        }
        var c = Set<AnyCancellable>()

        let manager = appState.menuBarManager
        let states = manager.sections
            .filter { $0.name != .visible }
            .map { $0.controlItem.$state.mapToVoid().eraseToAnyPublisher() }
        let visibility = manager.sections
            .filter { $0.name == .alwaysHidden }
            .map { $0.controlItem.$isVisible.mapToVoid().eraseToAnyPublisher() }
        // `@Published` sinks run before the new value is stored; update on the
        // next pass so the new state is read.
        Publishers.MergeMany(states + visibility)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] in
                self?.update()
            }
            .store(in: &c)

        // An assertion allows the applications running when it was made, so
        // one launched later would be hidden until the next update. Agents
        // (most menu bar apps) never post the launch notification, hence the
        // running applications themselves are observed.
        NSWorkspace.shared.publisher(for: \.runningApplications)
            .map { Set($0.compactMap(\.bundleIdentifier)) }
            .removeDuplicates()
            .dropFirst()
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.update()
            }
            .store(in: &c)

        // Attaching or removing a display switches between this backend and
        // the spacers. The dividers collapse first; wait for the bar to
        // settle so the sections can be read from it.
        NotificationCenter.default.publisher(for: NSApplication.didChangeScreenParametersNotification)
            .debounce(for: .milliseconds(600), scheduler: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.update()
            }
            .store(in: &c)

        NotificationCenter.default.publisher(for: NSApplication.willTerminateNotification)
            .sink { [weak self] _ in
                self?.releaseAll()
            }
            .store(in: &c)

        cancellables = c

        // Status items take a moment to be laid out after launch.
        Task { [weak self] in
            try? await Task.sleep(for: .seconds(1))
            self?.update()
        }
    }

    // MARK: Update

    /// Hides what the sections' states call for.
    func update() {
        guard #available(macOS 27, *) else {
            return
        }
        if let suspendedUntil, ContinuousClock.now < suspendedUntil {
            return
        }
        updateGeneration += 1
        let generation = updateGeneration
        let previous = applyTask
        applyTask = Task { [weak self] in
            await previous?.value
            guard let self, generation == updateGeneration else {
                return
            }
            await apply()
        }
    }

    @available(macOS 27, *)
    private func apply() async {
        guard let appState, Self.isInUse else {
            if wasInUse {
                wasInUse = false
                releaseAll()
                Logger.concealer.info("Switched to spacer hiding")
            }
            return
        }
        if !wasInUse {
            wasInUse = true
            Logger.concealer.info("Switched to assessment-mode hiding")
        }
        let state = revealState(appState)
        // Nothing hidden means every item and Ice's dividers are drawn: the
        // one moment the sections can be read from the bar.
        if live == nil, state != .allRevealed {
            await learnSections()
        }
        let running = Set(NSWorkspace.shared.runningApplications.compactMap(\.bundleIdentifier))
        let concealed = concealedApps(for: state, alwaysHiddenEnabled: isAlwaysHiddenEnabled(appState))
            .intersection(running)
        guard !concealed.isEmpty else {
            releaseAll()
            return
        }
        let needed = running.subtracting(concealed)
        // Every change makes MenuBarAgent lay the bar out again. An app that
        // quit can stay allowed, so only a newly launched one needs a change.
        if let live, live.concealed == concealed, needed.isSubset(of: live.allowed) {
            return
        }
        let allowed = needed.sorted()
        do {
            // The new assertion goes live before the old one is released, so
            // an app hidden on both sides of the change never flickers.
            let token = try await AssessmentAssertion.activate(allowedBundleIDs: allowed)
            if let old = live {
                AssessmentAssertion.invalidate(old.token)
            }
            live = (token, concealed, allowed)
            clickTap.enable()
            Logger.concealer.info("Hiding \(concealed.sorted())")
        } catch {
            Logger.concealer.error("Couldn't hide menu bar items: \(error)")
        }
    }

    /// Releases the live assertion, which brings every item back.
    private func releaseAll() {
        guard let old = live else {
            return
        }
        live = nil
        clickTap.disable()
        if #available(macOS 27, *) {
            AssessmentAssertion.invalidate(old.token)
        }
    }

    // MARK: Sections

    private func revealState(_ appState: AppState) -> RevealState {
        let manager = appState.menuBarManager
        if
            let alwaysHidden = manager.section(withName: .alwaysHidden),
            alwaysHidden.isEnabled,
            alwaysHidden.controlItem.state == .showItems
        {
            return .allRevealed
        }
        if manager.section(withName: .hidden)?.controlItem.state == .showItems {
            return .hiddenRevealed
        }
        return .allHidden
    }

    private func isAlwaysHiddenEnabled(_ appState: AppState) -> Bool {
        appState.menuBarManager.section(withName: .alwaysHidden)?.isEnabled == true
    }

    /// The learned section of each application: 1 hidden, 2 always hidden.
    /// Applications missing from it are visible.
    private var savedSections: [String: Int] {
        get {
            UserDefaults.standard.dictionary(forKey: Self.sectionsKey) as? [String: Int] ?? [:]
        }
        set {
            UserDefaults.standard.set(newValue, forKey: Self.sectionsKey)
        }
    }

    /// The applications to hide in the given state.
    private func concealedApps(for state: RevealState, alwaysHiddenEnabled: Bool) -> Set<String> {
        let minimum: Int
        switch state {
        case .allHidden: minimum = 1
        // Without the always-hidden section its apps count as hidden.
        case .hiddenRevealed: minimum = alwaysHiddenEnabled ? 2 : 3
        case .allRevealed: minimum = 3
        }
        return Set(savedSections.filter { $0.value >= minimum }.keys).subtracting(Self.neverHidden)
    }

    /// Reads each application's section from where its items sit relative to
    /// Ice's dividers, the way the spacers draw the sections.
    ///
    /// Only items drawn on the same display as the hidden divider count, so
    /// an item in overflow (no frame) keeps its last learned section. An app
    /// with items in several sections takes the most visible one, so nothing
    /// meant to stay visible is hidden with it.
    private func learnSections() async {
        guard let appState else {
            return
        }
        let apps = NSWorkspace.shared.runningApplications
        let alwaysHiddenEnabled = isAlwaysHiddenEnabled(appState)
        let (frames, items) = await Task.detached(priority: .userInitiated) {
            (MenuBarItemAXDiscovery.ownElementFrames(), MenuBarItemAXDiscovery.discoverItems(in: apps))
        }.value
        guard
            let hidden = frames["IceHiddenDivider"],
            let display = Self.menuBarDisplay(containing: hidden)
        else {
            return
        }
        let alwaysHidden = alwaysHiddenEnabled
            ? frames["IceAlwaysHiddenDivider"].flatMap { Self.menuBarDisplay(containing: $0) == display ? $0 : nil }
            : nil
        var learned = [String: Int]()
        for item in items {
            guard
                let bundleID = item.bundleID,
                !Self.neverHidden.contains(bundleID),
                let frame = item.axFrame,
                frame.width > 0,
                Self.menuBarDisplay(containing: frame) == display
            else {
                continue
            }
            let section = if let alwaysHidden, frame.midX < alwaysHidden.midX {
                2
            } else if frame.midX < hidden.midX {
                1
            } else {
                0
            }
            learned[bundleID] = min(learned[bundleID] ?? section, section)
        }
        guard !learned.isEmpty else {
            return
        }
        var sections = savedSections
        for (bundleID, section) in learned {
            sections[bundleID] = section == 0 ? nil : section
        }
        if sections != savedSections {
            savedSections = sections
            Logger.concealer.info("Learned sections: \(sections)")
        }
    }

    /// The display whose menu bar strip holds a frame (AX coordinates).
    private static func menuBarDisplay(containing frame: CGRect) -> CGDirectDisplayID? {
        guard frame.minX.isFinite, frame.minY.isFinite, frame.width.isFinite else {
            return nil
        }
        let center = CGPoint(x: frame.midX, y: frame.midY)
        return NSScreen.screens.lazy.map(\.displayID).first { displayID in
            let bounds = CGDisplayBounds(displayID)
            return bounds.contains(center) && center.y < bounds.minY + 40
        }
    }

    // MARK: Click Bridge

    /// Marks the clicks Ice replays, so the tap lets them through.
    private static let replayMarker: Int64 = 0x1CE_27_C1C

    /// How long hiding stays lifted around a replayed click. Ice PR #995
    /// measured on macOS 27.0 that 60ms loses a click now and then and 80ms
    /// and up never do.
    private static let clickLift = Duration.milliseconds(120)

    /// System items that ignore an Accessibility press (measured on macOS
    /// 27.0); others are pressed first, which needs no lift.
    private var itemsIgnoringPress: Set<String> = [
        "com.apple.menuextra.clock",
        "com.apple.menuextra.battery",
        "com.apple.menuextra.wifi",
    ]

    /// The system item whose panel a bridged click last opened.
    private var itemShowingPanel: String?

    /// The release of a held-back press is held back with it until then.
    private var heldReleaseUntil: ContinuousClock.Instant?

    /// Holds back clicks on system items while anything is hidden.
    private lazy var clickTap = EventTap(
        label: "Concealer click bridge",
        options: .defaultTap,
        location: .hidEventTap,
        place: .headInsertEventTap,
        types: [.leftMouseDown, .leftMouseUp]
    ) { [weak self] proxy, type, event in
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            proxy.enable()
            return event
        }
        return self?.handleClick(type: type, event: event) ?? event
    }

    private func handleClick(type: CGEventType, event: CGEvent) -> CGEvent? {
        guard event.getIntegerValueField(.eventSourceUserData) != Self.replayMarker else {
            return event
        }
        if type == .leftMouseUp {
            guard let until = heldReleaseUntil, ContinuousClock.now < until else {
                heldReleaseUntil = nil
                return event
            }
            heldReleaseUntil = nil
            return nil
        }
        guard
            isConcealing,
            let item = Self.systemItem(at: event.location)
        else {
            return event
        }
        heldReleaseUntil = .now + .seconds(1)
        let location = event.location
        Task { [weak self] in
            await self?.bridge(clickAt: location, on: item)
        }
        return nil
    }

    /// Gets a held-back click to a system item.
    private func bridge(clickAt location: CGPoint, on item: (element: AXUIElement, identifier: String)) async {
        // A click while a system panel is up is the click that closes it,
        // and Escape does that without lifting the hiding.
        if Self.openPanelWindow() != nil {
            Self.postEscape()
            guard item.identifier != itemShowingPanel else {
                itemShowingPanel = nil
                return
            }
            try? await Task.sleep(for: .milliseconds(120))
        }
        // Control Center opens from a press while items are hidden.
        if !itemsIgnoringPress.contains(item.identifier) {
            let before = Self.windowNumbers()
            await Self.press(item.element)
            if await Self.waitForPanel(after: before) {
                itemShowingPanel = item.identifier
                return
            }
            itemsIgnoringPress.insert(item.identifier)
        }
        await suspend(for: Self.clickLift)
        Self.replayClick(at: location)
        itemShowingPanel = item.identifier
    }

    /// Lifts the hiding for a moment and returns once it is really gone.
    private func suspend(for duration: Duration) async {
        suspendedUntil = .now + duration
        let previous = applyTask
        let release = Task { [weak self] in
            await previous?.value
            self?.releaseAll()
        }
        applyTask = release
        await release.value
        Task { [weak self] in
            try? await Task.sleep(for: duration)
            self?.suspendedUntil = nil
            self?.update()
        }
    }

    /// The system item at a point (CoreGraphics coordinates), if any.
    ///
    /// Asks Accessibility what is there rather than using cached frames:
    /// unlike other apps' items, MenuBarAgent reports the right element on
    /// every display.
    private static func systemItem(at point: CGPoint) -> (element: AXUIElement, identifier: String)? {
        guard
            let bounds = NSScreen.screens.lazy.map({ CGDisplayBounds($0.displayID) }).first(where: { $0.contains(point) }),
            point.y < bounds.minY + 40
        else {
            return nil
        }
        let systemWide = AXUIElementCreateSystemWide()
        AXUIElementSetMessagingTimeout(systemWide, 0.25)
        var element: AXUIElement?
        guard
            AXUIElementCopyElementAtPosition(systemWide, Float(point.x), Float(point.y), &element) == .success,
            let element
        else {
            return nil
        }
        var pid: pid_t = 0
        AXUIElementGetPid(element, &pid)
        guard NSRunningApplication(processIdentifier: pid)?.bundleIdentifier == "com.apple.MenuBarAgent" else {
            return nil
        }
        var identifier: CFTypeRef?
        AXUIElementCopyAttributeValue(element, "AXIdentifier" as CFString, &identifier)
        return (element, identifier as? String ?? "")
    }

    /// The processes that draw the system items' panels.
    private static let panelOwners: Set<String> = [
        "com.apple.notificationcenterui",
        "com.apple.controlcenter",
    ]

    /// An open system panel's window: at or above the menu bar's level, and
    /// taller than the bar (measured on macOS 27.0: Notification Center at
    /// layer 21, Control Center at 101).
    private static func openPanelWindow(excluding before: Set<Int> = []) -> Int? {
        let owners = Set(
            NSWorkspace.shared.runningApplications
                .filter { panelOwners.contains($0.bundleIdentifier ?? "") }
                .map(\.processIdentifier)
        )
        let windows = CGWindowListCopyWindowInfo([.optionOnScreenOnly], kCGNullWindowID) as? [[String: Any]] ?? []
        return windows.lazy.compactMap { window -> Int? in
            guard
                let number = window[kCGWindowNumber as String] as? Int,
                !before.contains(number),
                let layer = window[kCGWindowLayer as String] as? Int,
                layer >= 20,
                let owner = window[kCGWindowOwnerPID as String] as? pid_t,
                owners.contains(owner),
                let bounds = window[kCGWindowBounds as String] as? [String: CGFloat],
                (bounds["Height"] ?? 0) > 150
            else {
                return nil
            }
            return number
        }.first
    }

    private static func windowNumbers() -> Set<Int> {
        let windows = CGWindowListCopyWindowInfo([.optionOnScreenOnly], kCGNullWindowID) as? [[String: Any]] ?? []
        return Set(windows.compactMap { $0[kCGWindowNumber as String] as? Int })
    }

    private static func waitForPanel(after before: Set<Int>) async -> Bool {
        for _ in 0..<5 {
            try? await Task.sleep(for: .milliseconds(50))
            if openPanelWindow(excluding: before) != nil {
                return true
            }
        }
        return false
    }

    /// Presses an element off the main thread, which the call can block.
    private static func press(_ element: AXUIElement) async {
        await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                _ = AXUIElementPerformAction(element, kAXPressAction as CFString)
                continuation.resume()
            }
        }
    }

    private static func postEscape() {
        let source = CGEventSource(stateID: .hidSystemState)
        for down in [true, false] {
            CGEvent(keyboardEventSource: source, virtualKey: 53, keyDown: down)?.post(tap: .cghidEventTap)
        }
    }

    private static func replayClick(at location: CGPoint) {
        let source = CGEventSource(stateID: .hidSystemState)
        for type in [CGEventType.leftMouseDown, .leftMouseUp] {
            guard let event = CGEvent(
                mouseEventSource: source,
                mouseType: type,
                mouseCursorPosition: location,
                mouseButton: .left
            ) else {
                continue
            }
            event.setIntegerValueField(.eventSourceUserData, value: replayMarker)
            event.post(tap: .cghidEventTap)
        }
    }
}

// MARK: - AssessmentAssertion

/// MenuBarAgent's assessment mode (private `MenuBarClientCore`).
///
/// A configuration lists the numbered system items and the bundle identifiers
/// that stay on the bar. While an assertion is live, every other app's items
/// leave the bar on every display. It must be held by an app bundle: from a
/// command line tool the call succeeds and hides nothing. Ad-hoc signing is
/// enough (measured on macOS 27.2).
@available(macOS 27, *)
@MainActor
private enum AssessmentAssertion {
    enum Failure: Error, CustomStringConvertible {
        case unavailable
        case rejected(String)
        case timedOut

        var description: String {
            switch self {
            case .unavailable: "MenuBarClientCore is unavailable"
            case .rejected(let reason): "MenuBarAgent rejected the assertion: \(reason)"
            case .timedOut: "MenuBarAgent did not answer within 3 seconds"
            }
        }
    }

    /// Guards a continuation shared by a completion handler and a timeout.
    private final class OneShot: @unchecked Sendable {
        private let lock = NSLock()
        private var claimed = false

        func claim() -> Bool {
            lock.lock()
            defer {
                claimed = true
                lock.unlock()
            }
            return !claimed
        }
    }

    private static let frameworkPath = "/System/Library/PrivateFrameworks/MenuBarClientCore.framework/MenuBarClientCore"
    private static let configureSelector = NSSelectorFromString("initWithAllowedSystemItems:allowedBundleIdentifiers:")
    private static let activateSelector = NSSelectorFromString("activateWithConfiguration:completionHandler:")
    private static let invalidateSelector = NSSelectorFromString("invalidate")

    /// MenuBarAgent numbers its system items from 0 (0 through 8 on macOS
    /// 27.0); numbers with no item behind them are ignored, so later ones
    /// are allowed too.
    private static let systemItems = (0...63).map { NSNumber(value: $0) } as NSArray

    private static let classes: (configuration: AnyClass, assertion: AnyClass)? = {
        guard
            dlopen(frameworkPath, RTLD_NOW) != nil,
            let configuration = NSClassFromString("MBAssessmentModeConfiguration"),
            let assertion = NSClassFromString("MBAssessmentModeAssertion"),
            configuration.instancesRespond(to: configureSelector),
            assertion.instancesRespond(to: activateSelector),
            assertion.instancesRespond(to: invalidateSelector)
        else {
            return nil
        }
        return (configuration, assertion)
    }()

    /// Whether this macOS build offers the assertion.
    static var isAvailable: Bool {
        classes != nil
    }

    /// Activates an assertion that keeps only the given apps' items.
    static func activate(allowedBundleIDs: [String]) async throws -> AnyObject {
        guard
            let classes,
            let configuration = (classes.configuration.alloc() as AnyObject)
                .perform(configureSelector, with: systemItems, with: allowedBundleIDs as NSArray)?
                .takeUnretainedValue(),
            let assertion = (classes.assertion.alloc() as AnyObject)
                .perform(NSSelectorFromString("init"))?
                .takeUnretainedValue()
        else {
            throw Failure.unavailable
        }
        do {
            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
                let oneShot = OneShot()
                let completion: @convention(block) (Any?) -> Void = { error in
                    guard oneShot.claim() else {
                        return
                    }
                    if let error {
                        continuation.resume(throwing: Failure.rejected(String(describing: error)))
                    } else {
                        continuation.resume()
                    }
                }
                _ = assertion.perform(activateSelector, with: configuration, with: completion)
                DispatchQueue.main.asyncAfter(deadline: .now() + 3) {
                    guard oneShot.claim() else {
                        return
                    }
                    continuation.resume(throwing: Failure.timedOut)
                }
            }
        } catch {
            _ = assertion.perform(invalidateSelector)
            throw error
        }
        return assertion
    }

    /// Releases an assertion.
    static func invalidate(_ assertion: AnyObject) {
        _ = assertion.perform(invalidateSelector)
    }
}

// MARK: - Logger

private extension Logger {
    static let concealer = Logger(category: "Concealer")
}
