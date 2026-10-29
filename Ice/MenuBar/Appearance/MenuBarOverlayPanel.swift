//
//  MenuBarOverlayPanel.swift
//  Ice
//

import AXSwift
import Cocoa
import Combine
import QuartzCore

// MARK: - Overlay Panel

/// A subclass of `NSPanel` that sits atop the menu bar to alter its appearance.
final class MenuBarOverlayPanel: NSPanel {
    /// Flags representing the updatable components of a panel.
    enum UpdateFlag: String, CustomStringConvertible {
        case applicationMenuFrame

        var description: String { rawValue }
    }

    /// The kind of validation that occurs before an update.
    private enum ValidationKind {
        case showing
        case updates
    }

    /// A context that manages panel update tasks.
    private final class UpdateTaskContext {
        private var tasks = [UpdateFlag: Task<Void, any Error>]()

        /// Sets the task for the given update flag.
        ///
        /// Setting the task cancels the previous task for the flag, if there is one.
        ///
        /// - Parameters:
        ///   - flag: The update flag to set the task for.
        ///   - timeout: The timeout of the task.
        ///   - operation: The operation for the task to perform.
        func setTask(for flag: UpdateFlag, timeout: Duration, operation: @escaping () async throws -> Void) {
            cancelTask(for: flag)
            tasks[flag] = Task.detached(timeout: timeout) {
                try await operation()
            }
        }

        /// Cancels the task for the given update flag.
        ///
        /// - Parameter flag: The update flag to cancel the task for.
        func cancelTask(for flag: UpdateFlag) {
            tasks.removeValue(forKey: flag)?.cancel()
        }
    }

    /// A Boolean value that indicates whether the panel needs to be shown.
    @Published var needsShow = false

    /// A Boolean value that indicates whether the user is dragging a menu bar item.
    @Published var isDraggingMenuBarItem = false

    /// Flags representing the components of the panel currently in need of an update.
    @Published private(set) var updateFlags = Set<UpdateFlag>()

    /// The frame of the application menu.
    @Published private(set) var applicationMenuFrame: CGRect?

    /// Storage for internal observers.
    private var cancellables = Set<AnyCancellable>()

    /// The context that manages panel update tasks.
    private let updateTaskContext = UpdateTaskContext()

    /// The shared app state.
    private(set) weak var appState: AppState?

    /// The screen that owns the panel.
    let owningScreen: NSScreen

    /// Creates an overlay panel with the given app state and owning screen.
    init(appState: AppState, owningScreen: NSScreen) {
        self.appState = appState
        self.owningScreen = owningScreen
        super.init(
            contentRect: .zero,
            styleMask: [.borderless, .fullSizeContentView, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        // Level 24 (same as the menu bar background): the tint is fully
        // opaque, so the panel must never sit above the status-item windows
        // (level 25) or it would cover the menu bar icons. show() orders it
        // just above the menu bar background window instead.
        self.level = .mainMenu
        self.title = "Menu Bar Overlay"
        self.backgroundColor = .clear
        self.hasShadow = false
        self.ignoresMouseEvents = true
        self.collectionBehavior = [.fullScreenNone, .ignoresCycle, .moveToActiveSpace]
        self.contentView = MenuBarOverlayPanelContentView()
        configureCancellables()
    }

    private func configureCancellables() {
        var c = Set<AnyCancellable>()

        // Show the panel on the active space.
        NSWorkspace.shared.notificationCenter
            .publisher(for: NSWorkspace.activeSpaceDidChangeNotification)
            .debounce(for: 0.1, scheduler: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.needsShow = true
            }
            .store(in: &c)

        // Redraw with the correct light/dark tint when the system
        // appearance changes. The stored configuration holds both variants,
        // so no publisher fires for the switch — trigger a redraw directly.
        DistributedNotificationCenter.default()
            .publisher(for: DistributedNotificationCenter.interfaceThemeChangedNotification)
            .debounce(for: 0.1, scheduler: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.contentView?.needsDisplay = true
            }
            .store(in: &c)

        // Update application menu frame when the menu bar owning or frontmost app changes.
        Publishers.Merge(
            NSWorkspace.shared.publisher(for: \.menuBarOwningApplication, options: .old)
                .combineLatest(NSWorkspace.shared.publisher(for: \.menuBarOwningApplication, options: .new))
                .compactMap { $0 == $1 ? nil : $0 },
            NSWorkspace.shared.publisher(for: \.frontmostApplication, options: .old)
                .combineLatest(NSWorkspace.shared.publisher(for: \.frontmostApplication, options: .new))
                .compactMap { $0 == $1 ? nil : $0 }
        )
        .removeDuplicates()
        .sink { [weak self] _ in
            guard
                let self,
                let appState
            else {
                return
            }
            let displayID = owningScreen.displayID
            updateTaskContext.setTask(for: .applicationMenuFrame, timeout: .seconds(10)) {
                var hasDoneInitialUpdate = false
                var consecutiveMisses = 0
                while true {
                    try Task.checkCancellation()
                    guard
                        let latestFrame = appState.menuBarManager.getApplicationMenuFrame(for: displayID),
                        latestFrame != self.applicationMenuFrame
                    else {
                        // ponytail: was 1ms spin (~1000 AX round-trips/s for up to 10s).
                        // Back off exponentially while the menu bar isn't resolving so
                        // boot/app-switch doesn't stall WindowServer IPC.
                        if hasDoneInitialUpdate {
                            try await Task.sleep(for: .seconds(1))
                        } else {
                            consecutiveMisses += 1
                            let backoffMs = Int64(min(50 * consecutiveMisses, 500))
                            try await Task.sleep(for: .milliseconds(backoffMs))
                        }
                        continue
                    }
                    consecutiveMisses = 0
                    self.insertUpdateFlag(.applicationMenuFrame)
                    hasDoneInitialUpdate = true
                }
            }
            Task {
                try? await Task.sleep(for: .milliseconds(100))
                if self.owningScreen != NSScreen.main {
                    self.updateTaskContext.cancelTask(for: .applicationMenuFrame)
                }
            }
        }
        .store(in: &c)

        // Special cases for when the user drags an app onto or clicks into another space.
        Publishers.Merge(
            publisher(for: \.isOnActiveSpace)
                .receive(on: DispatchQueue.main)
                .mapToVoid(),
            UniversalEventMonitor.publisher(for: .leftMouseUp)
                .filter { [weak self] _ in self?.isOnActiveSpace ?? false }
                .mapToVoid()
        )
        .debounce(for: 0.05, scheduler: DispatchQueue.main)
        .sink { [weak self] in
            self?.insertUpdateFlag(.applicationMenuFrame)
        }
        .store(in: &c)

        Timer.publish(every: 10, on: .main, in: .default)
            .autoconnect()
            .sink { [weak self] _ in
                self?.insertUpdateFlag(.applicationMenuFrame)
            }
            .store(in: &c)

        $needsShow
            .debounce(for: 0.05, scheduler: DispatchQueue.main)
            .sink { [weak self] needsShow in
                guard let self, needsShow else {
                    return
                }
                defer {
                    self.needsShow = false
                }
                show()
            }
            .store(in: &c)

        $updateFlags
            .sink { [weak self] flags in
                guard let self, !flags.isEmpty else {
                    return
                }
                Task {
                    // Must be run async, or this will not remove the flags.
                    self.updateFlags.removeAll()
                }
                let windows = WindowInfo.getOnScreenWindows()
                guard let owningDisplay = self.validate(for: .updates, with: windows) else {
                    return
                }
                performUpdates(for: flags, windows: windows, display: owningDisplay)
            }
            .store(in: &c)

        if let appState {
            appState.menuBarManager.$isMenuBarHiddenBySystem
                .sink { [weak self] isHidden in
                    self?.alphaValue = isHidden ? 0 : 1
                }
                .store(in: &c)
        }

        cancellables = c
    }

    /// Inserts the given update flag into the panel's current list of update flags.
    private func insertUpdateFlag(_ flag: UpdateFlag) {
        updateFlags.insert(flag)
    }

    /// Performs validation for the given validation kind. Returns the panel's
    /// owning display if successful. Returns `nil` on failure.
    private func validate(for kind: ValidationKind, with windows: [WindowInfo]) -> CGDirectDisplayID? {
        lazy var actionMessage = switch kind {
        case .showing: "Preventing overlay panel from showing."
        case .updates: "Preventing overlay panel from updating."
        }
        guard let appState else {
            Logger.overlayPanel.debug("No app state. \(actionMessage)")
            return nil
        }
        guard !appState.menuBarManager.isMenuBarHiddenBySystemUserDefaults else {
            Logger.overlayPanel.debug("Menu bar is hidden by system. \(actionMessage)")
            return nil
        }
        guard !appState.isActiveSpaceFullscreen else {
            Logger.overlayPanel.debug("Active space is fullscreen. \(actionMessage)")
            return nil
        }
        let owningDisplay = owningScreen.displayID
        guard appState.menuBarManager.hasValidMenuBar(in: windows, for: owningDisplay) else {
            Logger.overlayPanel.debug("No valid menu bar found. \(actionMessage)")
            return nil
        }
        return owningDisplay
    }

    /// Stores the frame of the menu bar's application menu.
    private func updateApplicationMenuFrame(for display: CGDirectDisplayID) {
        guard
            let menuBarManager = appState?.menuBarManager,
            !menuBarManager.isMenuBarHiddenBySystem
        else {
            return
        }
        applicationMenuFrame = menuBarManager.getApplicationMenuFrame(for: display)
    }

    /// Updates the panel to prepare for display.
    private func performUpdates(for flags: Set<UpdateFlag>, windows: [WindowInfo], display: CGDirectDisplayID) {
        if flags.contains(.applicationMenuFrame) {
            updateApplicationMenuFrame(for: display)
        }
    }

    /// Shows the panel.
    private func show() {
        guard
            let appState,
            !appState.isPreview
        else {
            return
        }

        guard appState.appearanceManager.overlayPanels.contains(self) else {
            Logger.overlayPanel.warning("Overlay panel \(self) not retained")
            return
        }

        guard let menuBarHeight = owningScreen.getMenuBarHeight() else {
            return
        }

        let newFrame = CGRect(
            x: owningScreen.frame.minX,
            y: (owningScreen.frame.maxY - menuBarHeight) - 5,
            width: owningScreen.frame.width,
            height: menuBarHeight + 5
        )

        alphaValue = 0
        setFrame(newFrame, display: false)
        orderFrontRegardless()
        // The tint is opaque: keep the panel below the status-item windows
        // (level 25) by pinning it just above the menu bar background window
        // (same level 24). Otherwise the pills would cover the menu bar icons.
        if let menuBarWindowID = WindowInfo.getMenuBarWindow(for: owningScreen.displayID)?.windowID {
            order(.above, relativeTo: Int(menuBarWindowID))
        }

        updateFlags = [.applicationMenuFrame]

        // ponytail: no animator() fade on show. Fading while the split shape is
        // still unresolved (AX pending) flashes a half-tinted gray bar and costs
        // a compositor animation at every space switch. Appear instantly; the
        // shape resolves into place via needsDisplay.
        if !appState.menuBarManager.isMenuBarHiddenBySystem {
            alphaValue = 1
        }
    }

    override func isAccessibilityElement() -> Bool {
        return false
    }
}

// MARK: - Content View

final class MenuBarOverlayPanelContentView: NSView {
    /// Width of the trailing pill currently drawn on the display (the visible-items region).
    ///
    /// Used by the Ice Bar (expanded spacer, garbage divider frames) to exclude
    /// items the user already sees on the menu bar. Prefers the width being
    /// drawn, then the predicted one, then the cache.
    /// Nil when nothing has been measured yet — callers show everything as before.
    static func currentTrailingVisibleWidth(for display: CGDirectDisplayID) -> CGFloat? {
        loadPersistedTrailingWidths()
        trailingStateLock.lock()
        let width = displayedTrailingWidth[display]
            ?? predictiveTarget[display]
            ?? trailingWidthCache[display]?.width
        trailingStateLock.unlock()
        guard let width, width > 0 else {
            return nil
        }
        return width
    }
    /// Last-known trailing status widths per display, shared across panels.
    ///
    /// Panels are recreated on display/space/config changes, so per-view
    /// memory forced a full AX re-learn (toggle on/off a few times) every
    /// time — including every cold boot. Shared statics + UserDefaults
    /// persistence mean the first draw already knows last session's widths;
    /// the background rescan only corrects them.
    ///
    /// The Accessibility fallback scan blocks in cross-process IPC, so it must
    /// never run inside `draw(_:)`. Draws read this cache (main thread only);
    /// stale entries trigger a background rescan that redisplays on completion.
    ///
    /// The caches below are also touched off-main — `applyQuickLeadingEdge` runs
    /// on a background queue and `currentTrailingVisibleWidth` is called from
    /// nonisolated async code — so concurrent `Dictionary` mutation could corrupt
    /// their storage. `NSLock` mirrors the guard in `ScreenCapture`. Not
    /// reentrant: every call site takes it once, never nested.
    private static let trailingStateLock = NSLock()
    private static var trailingWidthCache = [CGDirectDisplayID: (width: CGFloat, date: Date)]()

    /// Displays with a background trailing-width rescan in flight.
    private static var trailingWidthScanInFlight = Set<CGDirectDisplayID>()

    /// How long a cached trailing width is trusted before rescanning.
    ///
    /// Short enough that third-party trailing changes (Control Center
    /// sliders, clock/date width) re-measure quickly; the scan itself stays
    /// on a background queue, so the cost is one background sweep per TTL.
    private static let trailingWidthTTL: TimeInterval = 2

    /// Burst-rescan deadlines per display.
    ///
    /// While a hide/show slide animation is in flight, each completed scan
    /// chains another one so the trailing pill tracks the sliding icons
    /// instead of jumping on the TTL.
    private static var trailingBurstUntil = [CGDirectDisplayID: Date]()

    /// Which sections are open. Each level shows a different set of icons,
    /// so each gets its own remembered width.
    ///
    /// The levels nest: opening always-hidden also opens hidden, and closing
    /// hidden also closes always-hidden.
    private enum RevealLevel: Int, CaseIterable, Comparable {
        /// Hidden section put away (always-hidden with it).
        case concealed
        /// Hidden section open, always-hidden put away.
        case revealed
        /// Hidden and always-hidden sections both open.
        case alwaysHiddenRevealed

        /// Suffix of the persisted widths key.
        var defaultsKey: String {
            switch self {
            case .concealed: "concealed"
            case .revealed: "revealed"
            case .alwaysHiddenRevealed: "alwaysHiddenRevealed"
            }
        }

        static func < (lhs: Self, rhs: Self) -> Bool {
            lhs.rawValue < rhs.rawValue
        }
    }

    /// Settled trailing widths remembered per display and reveal level.
    ///
    /// A toggle moves between two of these, so the pill can start gliding
    /// toward the destination instantly — ~1s before the AX rescan lands.
    /// Concealed/revealed alone was not enough: with always-hidden enabled,
    /// "hidden open" and "both open" shared one slot, so every always-hidden
    /// toggle predicted the previous width (empty pill strip on close, icons
    /// outside the pill on open).
    private static var settledWidths = [CGDirectDisplayID: [RevealLevel: CGFloat]]()

    /// Reveal level last seen per display, to tell a toggle apart from the
    /// repeated control-item publishes that follow it.
    private static var lastRevealLevel = [CGDirectDisplayID: RevealLevel]()

    /// Until when a predicted toggle's icon slide may still be in flight.
    ///
    /// A sweep started before this measured the icons mid-slide (or the
    /// pre-toggle layout); applying it would yank the pill off a correct
    /// prediction, so its width is dropped and the sweep reruns.
    private static var slideSettlesAt = [CGDirectDisplayID: Date]()

    /// How long a toggle's native icon slide is given to land, including
    /// the round trip to the menu bar server.
    private static let slideDuration: TimeInterval = 0.4

    /// Displays with a post-slide rescan already scheduled.
    private static var slideRefreshPending = Set<CGDirectDisplayID>()

    /// Width the pill was headed for right before a predicted toggle.
    ///
    /// AX can keep reporting the old layout after the icons have moved
    /// (seen under screen-capture load). A rescan that lands nearer this
    /// than the prediction is treated as stale while the burst lasts, so the
    /// pill doesn't bounce back to where it came from.
    private static var toggleOriginWidth = [CGDirectDisplayID: CGFloat]()

    /// Predictive target per display. Draws glide to this instead of the
    /// stale cache while a toggle (or cold boot) is resolving; cleared when
    /// a rescan measures the real width.
    private static var predictiveTarget = [CGDirectDisplayID: CGFloat]()

    /// When the last local (quick) leading-edge measure ran per display.
    ///
    /// Rate limit so one toggle can't queue a dozen overlapping AX walks.
    private static var trailingQuickRanAt = [CGDirectDisplayID: Date]()

    /// Currently drawn trailing width per display.
    ///
    /// Eases toward the target in both directions, so the pill glides with
    /// the sliding icons instead of jumping to its final size.
    private static var displayedTrailingWidth = [CGDirectDisplayID: CGFloat]()

    /// Time constant of the ease when the pill grows, in seconds.
    ///
    /// Exponential ease-out covers ~95% of the distance in 3τ (~0.1s here):
    /// quick enough that revealed icons don't sit outside the pill.
    private static let trailingExpandTimeConstant: CFTimeInterval = 0.035

    /// Time constant of the ease when the pill shrinks, in seconds (~0.18s
    /// to 95%), close to the icons sliding away.
    private static let trailingCollapseTimeConstant: CFTimeInterval = 0.06

    /// Display-synced driver that advances the ease. Created on demand,
    /// stopped as soon as the width lands — never a perpetual redraw.
    private var trailingEaseLink: CADisplayLink?

    /// Target time of the previous ease frame, for frame-rate-independent steps.
    private var trailingEaseLastTimestamp: CFTimeInterval?

    /// Whether persisted trailing widths have been loaded this launch.
    private static var trailingWidthsLoaded = false

    /// UserDefaults key for persisted trailing widths.
    ///
    /// Bumped to v3: v2 learned widths captured mid-transition (and with
    /// Ice's own control window counted as a status icon) predict a pill ~110pt
    /// too wide that never collapses. Relearn from the current arrangement.
    private static let trailingWidthsDefaultsKey = "Ice.TrailingWidths.v3"

    /// Whether the trailing cluster on the display currently contains a
    /// full-bleed system background (screen-recording / screen-sharing pill).
    ///
    /// The system draws that pill edge-to-edge, taller and wider than its AX
    /// frame. Ice's pill insets by 1pt on non-notch screens, so without this
    /// the blue peeks out top/bottom/left. Set by the background AX scan,
    /// read synchronously on the draw path. Transient — never persisted.
    private static var trailingFullBleed = [CGDirectDisplayID: Bool]()

    /// Whether the system is currently showing a screen-capture indicator.
    ///
    /// Ground truth: while anything captures the screen (recording software,
    /// Discord share/stream included), Window Server owns `StatusIndicator`
    /// windows and MenuBarAgent draws a wide system pill whose AX frame is a
    /// normal 20x22 icon — ~9pt narrower per side than the paint. Height alone
    /// can't spot it, so this presence flag (cheap public CGWindowList read,
    /// no AX) drives the extra pad + full height.
    /// Maintained by the background scans; draws only read it.
    private static var screenCaptureActive = false

    /// Displays for which the split-shape auxiliary-area fallback fired.
    ///
    /// Logged once per display: the draw path runs on every redisplay while
    /// a measurement stays unavailable, so an unguarded log would spam.
    private static var splitFallbackLogged = Set<CGDirectDisplayID>()

    /// Logs the split-shape auxiliary-area fallback once per display.
    private static func logSplitFallbackOnce(for display: CGDirectDisplayID, side: String) {
        guard !splitFallbackLogged.contains(display) else {
            return
        }
        splitFallbackLogged.insert(display)
        Logger.overlayPanel.debug("Split \(side) measurement unknown — using auxiliary-area fallback on display \(display)")
    }

    /// Loads persisted trailing widths once per launch.
    ///
    /// Stored as `"<displayID>.<RevealLevel.defaultsKey>|cache": Double`.
    /// Cached entries load as stale (`.distantPast`) so the first draw paints
    /// the remembered pill instantly while a background rescan re-validates it.
    private static func loadPersistedTrailingWidths() {
        trailingStateLock.lock()
        guard !trailingWidthsLoaded else {
            trailingStateLock.unlock()
            return
        }
        trailingWidthsLoaded = true
        trailingStateLock.unlock()
        guard let dict = UserDefaults.standard.dictionary(forKey: trailingWidthsDefaultsKey) as? [String: Double] else {
            return
        }
        trailingStateLock.lock()
        defer { trailingStateLock.unlock() }
        for (key, value) in dict {
            let parts = key.split(separator: ".")
            guard
                parts.count == 2,
                let display = CGDirectDisplayID(String(parts[0]))
            else {
                continue
            }
            let width = CGFloat(value)
            guard width > 0, width < 2000 else {
                continue
            }
            let suffix = String(parts[1])
            if suffix == "cache" {
                if trailingWidthCache[display] == nil {
                    trailingWidthCache[display] = (width, .distantPast)
                }
            } else if let level = RevealLevel.allCases.first(where: { $0.defaultsKey == suffix }) {
                settledWidths[display, default: [:]][level] = width
            }
        }
    }

    /// Persists the learned trailing widths for the next launch.
    private static func persistTrailingWidths() {
        trailingStateLock.lock()
        defer { trailingStateLock.unlock() }
        var dict = [String: Double]()
        for (display, widths) in settledWidths {
            for (level, width) in widths {
                dict["\(display).\(level.defaultsKey)"] = Double(width)
            }
        }
        for (display, entry) in trailingWidthCache where entry.width > 0 {
            dict["\(display).cache"] = Double(entry.width)
        }
        UserDefaults.standard.set(dict, forKey: trailingWidthsDefaultsKey)
    }

    /// Returns the remembered settled width for the display and level.
    ///
    /// - Parameter exact: when `false`, falls back to the nearest learned
    ///   level (fresh install, cold boot): a slightly wrong pill beats a
    ///   missing one. Toggle predictions pass `true`, because another
    ///   level's width is simply the wrong destination.
    private static func settledWidth(for display: CGDirectDisplayID, level: RevealLevel?, exact: Bool = false) -> CGFloat? {
        trailingStateLock.lock()
        defer { trailingStateLock.unlock() }
        guard let widths = settledWidths[display] else {
            return nil
        }
        if let level, let width = widths[level] {
            return width
        }
        guard !exact else {
            return nil
        }
        let fallbackOrder: [RevealLevel] = switch level {
        case .concealed: [.revealed, .alwaysHiddenRevealed]
        case .revealed: [.concealed, .alwaysHiddenRevealed]
        case .alwaysHiddenRevealed: [.revealed, .concealed]
        case nil: RevealLevel.allCases
        }
        return fallbackOrder.lazy.compactMap { widths[$0] }.first
    }

    /// Remembers the settled width for the display and level.
    private static func setSettledWidth(_ width: CGFloat, for display: CGDirectDisplayID, level: RevealLevel) {
        trailingStateLock.lock()
        settledWidths[display, default: [:]][level] = width
        trailingStateLock.unlock()
    }

    /// Sets (or clears) the predictive target. Locked: the Ice Bar reads it
    /// off the main thread via `currentTrailingVisibleWidth`.
    private static func setPredictiveTarget(_ width: CGFloat?, for display: CGDirectDisplayID) {
        trailingStateLock.lock()
        predictiveTarget[display] = width
        trailingStateLock.unlock()
    }

    /// Sets the drawn width. Locked for the same reason as the target; it
    /// changes every frame while the pill glides.
    private static func setDisplayedTrailingWidth(_ width: CGFloat, for display: CGDirectDisplayID) {
        trailingStateLock.lock()
        displayedTrailingWidth[display] = width
        trailingStateLock.unlock()
    }

    /// The width the pill is gliding toward.
    private static func trailingTarget(for display: CGDirectDisplayID) -> CGFloat {
        predictiveTarget[display] ?? trailingWidthCache[display]?.width ?? 0
    }

    /// Measures the leading edge locally and applies it as the drawn width.
    ///
    /// Split out of `refreshTrailingStatusWidth` so the quick measure can also
    /// run while a full sweep is in flight (the sweep blocks on nothing, but it
    /// takes ~1s; the local walk is ~0.1s and independent of it).
    private func applyQuickLeadingEdge(for display: CGDirectDisplayID, verdict: EdgeVerdict) {
        // ponytail: one quick measure per 0.2s per display. A toggle fires
        // $isVisible + $windowFrame for every control item (5+ calls), which
        // was 5 overlapping AX walks for the same answer.
        let now = Date()
        // Check + stamp in one critical section; otherwise two walks started
        // microseconds apart both pass the gate.
        Self.trailingStateLock.lock()
        let allowed = Self.trailingQuickRanAt[display].map({ now.timeIntervalSince($0) > 0.2 }) ?? true
        if allowed {
            Self.trailingQuickRanAt[display] = now
        }
        Self.trailingStateLock.unlock()
        guard allowed else {
            return
        }
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let quickWidth = Self.quickLeadingEdgeWidth(for: display, verdict: verdict) else {
                Logger.overlayPanel.debug("Quick edge \(display): verdict=\(verdict) -> nil")
                return
            }
            Logger.overlayPanel.debug("Quick edge \(display): verdict=\(verdict) -> \(quickWidth)")
            DispatchQueue.main.async {
                // Cache only — never pin `predictiveTarget` from a local walk:
                // a walk taken while the section is still sliding measures
                // icons mid-flight, and pinning that made the pill stick.
                Self.trailingWidthCache[display] = (quickWidth, Date())
                self?.needsDisplay = true
            }
        }
    }

    /// Which sections are currently open, if known.
    private func revealLevel() -> RevealLevel? {
        guard
            let menuBarManager = overlayPanel?.appState?.menuBarManager,
            let hiddenSection = menuBarManager.section(withName: .hidden)
        else {
            return nil
        }
        if hiddenSection.controlItem.state == .hideItems {
            return .concealed
        }
        if
            let alwaysHiddenSection = menuBarManager.section(withName: .alwaysHidden),
            alwaysHiddenSection.isEnabled,
            alwaysHiddenSection.controlItem.state == .showItems
        {
            return .alwaysHiddenRevealed
        }
        return .revealed
    }

    /// Seeds the predictive target from remembered widths, so the first
    /// draw after boot opens at the right size, not 0.
    ///
    /// Only until the first live measurement lands. This runs on every
    /// draw, and re-seeding whenever the target was empty put the remembered
    /// width straight back after each rescan cleared it, so the pill ignored
    /// real measurements until the scan burst settled (1.5s+ per toggle).
    private func seedPredictionIfNeeded(for display: CGDirectDisplayID) {
        Self.loadPersistedTrailingWidths()
        guard
            Self.predictiveTarget[display] == nil,
            Self.trailingWidthCache[display].map({ $0.date == .distantPast }) ?? true
        else {
            return
        }
        if
            let remembered = Self.settledWidth(for: display, level: revealLevel()),
            remembered > 0
        {
            Self.setPredictiveTarget(remembered, for: display)
        }
    }

    /// Predicts the trailing width after a toggle from one level to another.
    ///
    /// Applies the learned difference between the two levels to the width
    /// in use now, so changes that hit every level alike (clock text, a newly
    /// launched app's icon) don't skew it. Returns `nil` when the destination
    /// was never measured.
    private func predictedWidth(for display: CGDirectDisplayID, from origin: RevealLevel, to destination: RevealLevel) -> CGFloat? {
        guard
            let destinationWidth = Self.settledWidth(for: display, level: destination, exact: true),
            destinationWidth > 0
        else {
            return nil
        }
        guard
            let originWidth = Self.settledWidth(for: display, level: origin, exact: true),
            let current = Self.predictiveTarget[display] ?? Self.trailingWidthCache[display]?.width,
            current > 0,
            abs(current - originWidth) < 150
        else {
            // No usable base (or one far off the learned origin, i.e.
            // stale): the absolute destination is the safer bet.
            return destinationWidth
        }
        let predicted = current + (destinationWidth - originWidth)
        let screenWidth = CGDisplayBounds(display).width
        guard predicted > 0, screenWidth <= 0 || predicted < screenWidth else {
            return destinationWidth
        }
        return predicted
    }

    /// Frosted-glass blur of the live background, masked to the pills.
    ///
    /// Sits below `tintView`: blur first, then the (possibly translucent)
    /// tint on top.
    private lazy var blurView: NSVisualEffectView = {
        let view = NSVisualEffectView()
        view.material = .menu
        view.blendingMode = .behindWindow
        view.state = .active
        view.wantsLayer = true
        view.layer?.mask = blurMask
        return view
    }()

    /// Mask that clips `blurView` to the pills.
    private let blurMask = CAShapeLayer()

    /// Draws the pill tint (and border) above `blurView`.
    private lazy var tintView = MenuBarTintView()

    @Published private var fullConfiguration: MenuBarAppearanceConfigurationV2 = .defaultConfiguration

    @Published private var previewConfiguration: MenuBarAppearancePartialConfiguration?

    private var cancellables = Set<AnyCancellable>()

    /// The overlay panel that contains the content view.
    private var overlayPanel: MenuBarOverlayPanel? {
        window as? MenuBarOverlayPanel
    }

    /// The currently displayed configuration.
    private var configuration: MenuBarAppearancePartialConfiguration {
        previewConfiguration ?? fullConfiguration.current
    }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        // blurView below, tintView above: blur first, then tint on top.
        addSubview(blurView)
        addSubview(tintView)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        configureCancellables()
        guard let panel = overlayPanel else {
            // Detached: stop the ease driver, if running.
            stopTrailingEase()
            return
        }
        // Warm the shared trailing cache immediately so the first draw (and
        // cold boot) already has a width. Previously the scan only started
        // lazily inside draw(), adding ~1s of mismatched pill at login.
        let display = panel.owningScreen.displayID
        seedPredictionIfNeeded(for: display)
        refreshTrailingStatusWidth(for: display, force: false)
    }

    private func configureCancellables() {
        var c = Set<AnyCancellable>()

        if let overlayPanel {
            if let appState = overlayPanel.appState {
                appState.appearanceManager.$configuration
                    .removeDuplicates()
                    .assign(to: &$fullConfiguration)

                appState.appearanceManager.$previewConfiguration
                    .removeDuplicates()
                    .assign(to: &$previewConfiguration)

                for section in appState.menuBarManager.sections {
                    // Redraw whenever the window frame of a control item changes.
                    //
                    // - NOTE: A previous attempt was made to redraw the view when the
                    //   section's `isHidden` property was changed. This would be semantically
                    //   ideal, but the property sometimes changes before the menu bar items
                    //   are actually updated on-screen. Since the view's drawing process relies
                    //   on getting an accurate position of each menu bar item, we need to use
                    //   something that publishes its changes only after the items are updated.
                    section.controlItem.$windowFrame
                        .receive(on: DispatchQueue.main)
                        .sink { [weak self] _ in
                            self?.noteControlItemMoved()
                        }
                        .store(in: &c)

                    // Redraw whenever the visibility of a control item changes.
                    //
                    // - NOTE: If the "ShowSectionDividers" setting is disabled, the window
                    //   frame does not update when the section is hidden or shown, but the
                    //   visibility does. We observe both to ensure the update occurs.
                    section.controlItem.$isVisible
                        .receive(on: DispatchQueue.main)
                        .sink { [weak self] _ in
                            self?.noteControlItemMoved()
                        }
                        .store(in: &c)
                }
            }

            // Fade out whenever a menu bar item is being dragged.
            overlayPanel.$isDraggingMenuBarItem
                .removeDuplicates()
                .sink { [weak self] isDragging in
                    if isDragging {
                        self?.animator().alphaValue = 0
                    } else {
                        self?.animator().alphaValue = 1
                    }
                }
                .store(in: &c)
            // Redraw whenever the application menu frame changes.
            overlayPanel.$applicationMenuFrame
                .sink { [weak self] _ in
                    self?.needsDisplay = true
                }
                .store(in: &c)
        }

        // Redraw whenever the configurations change.
        $fullConfiguration.mapToVoid()
            .merge(with: $previewConfiguration.mapToVoid())
            .sink { [weak self] _ in
                self?.needsDisplay = true
            }
            .store(in: &c)

        // Third-party trailing changes (Control Center sliders, clock/date
        // width, minute rollover, freshly launched apps) don't move Ice's
        // control items, so none of the above fires. Redisplay on a backstop
        // interval; draws re-measure in the background when stale. The fast
        // edge check below is what catches changes quickly — this is only
        // the safety net.
        Timer.publish(every: 2, on: .main, in: .common)
            .autoconnect()
            .sink { [weak self] _ in
                self?.needsDisplay = true
            }
            .store(in: &c)

        // Fast edge check: a handful of AX probes around the currently drawn
        // edge, ~10x cheaper than a full sweep. Catches appeared/removed
        // icons within half a second instead of leaving them floating off
        // the pill until the next toggle or backstop tick.
        Timer.publish(every: 0.25, on: .main, in: .common)
            .autoconnect()
            .sink { [weak self] _ in
                self?.checkTrailingEdge()
            }
            .store(in: &c)

        // A newly launched or quit app often adds/removes a status icon with
        // no Ice control item moving at all — check the edge right away.
        Publishers.Merge(
            NSWorkspace.shared.notificationCenter
                .publisher(for: NSWorkspace.didLaunchApplicationNotification)
                .mapToVoid(),
            NSWorkspace.shared.notificationCenter
                .publisher(for: NSWorkspace.didTerminateApplicationNotification)
                .mapToVoid()
        )
        .debounce(for: 0.15, scheduler: DispatchQueue.main)
        .sink { [weak self] _ in
            self?.checkTrailingEdge()
        }
        .store(in: &c)

        cancellables = c
    }

    /// Returns a path in the given rectangle, with the given end caps,
    /// and inset by the given amounts.
    ///
    /// - Parameter fullHeight: skips the 1pt top/bottom inset on non-notch
    ///   screens so the pill covers a full-bleed system background
    ///   (screen-recording pill). Horizontal insets are kept.
    /// - Parameter cornerRadiusFactor: `0...1` curvature for `.round` end caps.
    ///   `1` is a fully round pill, `0` reads as square.
    private func shapePath(in rect: CGRect, leadingEndCap: MenuBarEndCap, trailingEndCap: MenuBarEndCap, screen: NSScreen, fullHeight: Bool = false, cornerRadiusFactor: Double = 1) -> NSBezierPath {
        let insetRect: CGRect = if !screen.hasNotch {
            switch (leadingEndCap, trailingEndCap, fullHeight) {
            case (.square, .square, true):
                CGRect(x: rect.origin.x, y: rect.origin.y, width: rect.width, height: rect.height)
            case (.square, .round, true):
                CGRect(x: rect.origin.x, y: rect.origin.y, width: rect.width - 1, height: rect.height)
            case (.round, .square, true):
                CGRect(x: rect.origin.x + 1, y: rect.origin.y, width: rect.width - 1, height: rect.height)
            case (.round, .round, true):
                CGRect(x: rect.origin.x + 1, y: rect.origin.y, width: rect.width - 2, height: rect.height)
            case (.square, .square, false):
                CGRect(x: rect.origin.x, y: rect.origin.y + 1, width: rect.width, height: rect.height - 2)
            case (.square, .round, false):
                CGRect(x: rect.origin.x, y: rect.origin.y + 1, width: rect.width - 1, height: rect.height - 2)
            case (.round, .square, false):
                CGRect(x: rect.origin.x + 1, y: rect.origin.y + 1, width: rect.width - 1, height: rect.height - 2)
            case (.round, .round, false):
                CGRect(x: rect.origin.x + 1, y: rect.origin.y + 1, width: rect.width - 2, height: rect.height - 2)
            }
        } else {
            rect
        }

        let clampedFactor = CGFloat(cornerRadiusFactor).clamped(to: 0...1)
        let maxRadius = insetRect.height / 2
        var leadingRadius: CGFloat = leadingEndCap == .round ? maxRadius * clampedFactor : 0
        var trailingRadius: CGFloat = trailingEndCap == .round ? maxRadius * clampedFactor : 0
        leadingRadius = min(leadingRadius, insetRect.width / 2)
        trailingRadius = min(trailingRadius, insetRect.width / 2)

        if leadingRadius <= 0, trailingRadius <= 0 {
            return NSBezierPath(rect: insetRect)
        }

        // Fully round: keep the exact stadium geometry (rect + oval caps).
        if leadingRadius >= maxRadius, trailingRadius >= maxRadius {
            let shapeBounds = CGRect(
                x: insetRect.minX + insetRect.height / 2,
                y: insetRect.minY,
                width: insetRect.width - insetRect.height,
                height: insetRect.height
            )
            let leadingEndCapBounds = CGRect(
                x: insetRect.minX,
                y: insetRect.minY,
                width: insetRect.height,
                height: insetRect.height
            )
            let trailingEndCapBounds = CGRect(
                x: insetRect.maxX - insetRect.height,
                y: insetRect.minY,
                width: insetRect.height,
                height: insetRect.height
            )

            var path = NSBezierPath(rect: shapeBounds)

            path = switch leadingEndCap {
            case .square: path.union(NSBezierPath(rect: leadingEndCapBounds))
            case .round: path.union(NSBezierPath(ovalIn: leadingEndCapBounds))
            }

            path = switch trailingEndCap {
            case .square: path.union(NSBezierPath(rect: trailingEndCapBounds))
            case .round: path.union(NSBezierPath(ovalIn: trailingEndCapBounds))
            }

            return path
        }

        // Partial rounding: per-side corner radii on the inset rect.
        let minX = insetRect.minX
        let minY = insetRect.minY
        let maxX = insetRect.maxX
        let maxY = insetRect.maxY
        let cgPath = CGMutablePath()
        cgPath.move(to: CGPoint(x: minX + leadingRadius, y: minY))
        cgPath.addLine(to: CGPoint(x: maxX - trailingRadius, y: minY))
        if trailingRadius > 0 {
            cgPath.addArc(center: CGPoint(x: maxX - trailingRadius, y: minY + trailingRadius), radius: trailingRadius, startAngle: -.pi / 2, endAngle: 0, clockwise: false)
            cgPath.addLine(to: CGPoint(x: maxX, y: maxY - trailingRadius))
            cgPath.addArc(center: CGPoint(x: maxX - trailingRadius, y: maxY - trailingRadius), radius: trailingRadius, startAngle: 0, endAngle: .pi / 2, clockwise: false)
        } else {
            cgPath.addLine(to: CGPoint(x: maxX, y: minY))
            cgPath.addLine(to: CGPoint(x: maxX, y: maxY))
        }
        cgPath.addLine(to: CGPoint(x: minX + leadingRadius, y: maxY))
        if leadingRadius > 0 {
            cgPath.addArc(center: CGPoint(x: minX + leadingRadius, y: maxY - leadingRadius), radius: leadingRadius, startAngle: .pi / 2, endAngle: .pi, clockwise: false)
            cgPath.addLine(to: CGPoint(x: minX, y: minY + leadingRadius))
            cgPath.addArc(center: CGPoint(x: minX + leadingRadius, y: minY + leadingRadius), radius: leadingRadius, startAngle: .pi, endAngle: 3 * .pi / 2, clockwise: false)
        } else {
            cgPath.addLine(to: CGPoint(x: minX, y: maxY))
            cgPath.addLine(to: CGPoint(x: minX, y: minY))
        }
        cgPath.closeSubpath()
        return NSBezierPath(cgPath: cgPath)
    }

    /// Returns a path for the ``MenuBarShapeKind/full`` shape kind.
    private func pathForFullShape(in rect: CGRect, info: MenuBarFullShapeInfo, isInset: Bool, screen: NSScreen) -> NSBezierPath {
        guard let appearanceManager = overlayPanel?.appState?.appearanceManager else {
            return NSBezierPath()
        }
        var rect = rect
        let shouldInset = isInset && screen.hasNotch
        if shouldInset {
            rect = rect.insetBy(dx: 0, dy: appearanceManager.menuBarInsetAmount)
            if info.leadingEndCap == .round {
                rect.origin.x += appearanceManager.menuBarInsetAmount
                rect.size.width -= appearanceManager.menuBarInsetAmount
            }
            if info.trailingEndCap == .round {
                rect.size.width -= appearanceManager.menuBarInsetAmount
            }
        }
        return shapePath(
            in: rect,
            leadingEndCap: info.leadingEndCap,
            trailingEndCap: info.trailingEndCap,
            screen: screen,
            fullHeight: Self.trailingFullBleed[screen.displayID] == true || Self.screenCaptureActive,
            cornerRadiusFactor: fullConfiguration.cornerRadius
        )
    }

    /// Returns a path for the ``MenuBarShapeKind/split`` shape kind.
    private func pathForSplitShape(in rect: CGRect, info: MenuBarSplitShapeInfo, isInset: Bool, screen: NSScreen) -> NSBezierPath {
        guard let appearanceManager = overlayPanel?.appState?.appearanceManager else {
            return NSBezierPath()
        }
        var rect = rect
        let shouldInset = isInset && screen.hasNotch
        if shouldInset {
            rect = rect.insetBy(dx: 0, dy: appearanceManager.menuBarInsetAmount)
            if info.leading.leadingEndCap == .round {
                rect.origin.x += appearanceManager.menuBarInsetAmount
                rect.size.width -= appearanceManager.menuBarInsetAmount
            }
            if info.trailing.trailingEndCap == .round {
                rect.size.width -= appearanceManager.menuBarInsetAmount
            }
        }
        let leadingPathBounds: CGRect = {
            if let width = overlayPanel?.applicationMenuFrame?.width, width > 0 {
                var maxX = width
                if shouldInset {
                    maxX += 10
                    if info.leading.leadingEndCap == .square {
                        maxX += appearanceManager.menuBarInsetAmount
                    }
                } else {
                    maxX += 20
                }
                return CGRect(x: rect.minX, y: rect.minY, width: maxX, height: rect.height)
            }
            // ponytail: AX app-menu frame unknown (probe miss). On notch screens
            // the system reserves the left auxiliary area for the app menu, so
            // bind the pill to it instead of dropping it — a lone trailing pill
            // reads as a "missing border" bug.
            guard
                screen.hasNotch,
                let leftArea = screen.auxiliaryTopLeftArea
            else {
                return .zero
            }
            Self.logSplitFallbackOnce(for: screen.displayID, side: "leading")
            let pad: CGFloat = shouldInset ? 10 : 20
            let width = max(0, leftArea.maxX - screen.frame.minX - rect.minX + pad)
            guard width > 0 else {
                return .zero
            }
            return CGRect(x: rect.minX, y: rect.minY, width: width, height: rect.height)
        }()
        // Full-bleed system pill (screen recording) needs a full-height
        // trailing pill, or the blue peeks out top/bottom. CGS branch reads
        // item heights synchronously; AX branch uses the background scan flag
        // plus the capture-indicator presence flag (its AX frame is a normal
        // 20x22 icon, so height alone can't spot it).
        var trailingFullHeight = Self.trailingFullBleed[screen.displayID] == true || Self.screenCaptureActive
        let trailingPathBounds: CGRect = {
            let items = MenuBarItem.getMenuBarItems(on: screen.displayID, onScreenOnly: true, activeSpaceOnly: false)
            if items.contains(where: { $0.frame.height >= rect.height - 4 }) {
                trailingFullHeight = true
            }
            let totalWidth: CGFloat = if items.isEmpty {
                // macOS 27: CGSGetProcessMenuBarWindowList no longer returns status
                // items, so fall back to a cached Accessibility-based estimate.
                // The live AX scan blocks in IPC and must stay off the draw path.
                cachedTrailingStatusWidth(for: screen.displayID)
            } else {
                // CGS frames track AX frames, not the wider system paint over an
                // active share/record pill, and the list can miss fresh icons
                // (new recording indicator). Floor with the padded AX estimate
                // so fresh indicators never end up off the pill.
                max(
                    items.reduce(into: 0) { width, item in
                        width += item.frame.width
                    },
                    cachedTrailingStatusWidth(for: screen.displayID)
                )
            }
            if totalWidth > 0 {
                var position = rect.maxX - totalWidth
                if shouldInset, info.trailing.trailingEndCap == .square {
                    position -= appearanceManager.menuBarInsetAmount
                }
                guard position < rect.maxX else {
                    return .zero
                }
                return CGRect(x: position, y: rect.minY, width: rect.maxX - position, height: rect.height)
            }
            // ponytail: CGS is empty on macOS 27+ and the AX rescan has no width
            // yet (roles/frames vary by OS, scan window capped). On notch screens
            // the system reserves the right auxiliary area for status items, so
            // bind the pill to it instead of dropping it — a slightly wide pill
            // with border beats a missing one.
            guard
                screen.hasNotch,
                let rightArea = screen.auxiliaryTopRightArea
            else {
                return .zero
            }
            Self.logSplitFallbackOnce(for: screen.displayID, side: "trailing")
            var position = rightArea.minX - screen.frame.minX
            if shouldInset, info.trailing.trailingEndCap == .square {
                position -= appearanceManager.menuBarInsetAmount
            }
            let clamped = min(max(position, rect.minX), rect.maxX)
            guard clamped < rect.maxX else {
                return .zero
            }
            return CGRect(x: clamped, y: rect.minY, width: rect.maxX - clamped, height: rect.height)
        }()

        let hasLeading = leadingPathBounds != .zero
        let hasTrailing = trailingPathBounds != .zero

        if hasLeading, hasTrailing {
            if leadingPathBounds.intersects(trailingPathBounds) {
                // Genuinely crowded bar: fall back to a full-width shape.
                return shapePath(
                    in: rect,
                    leadingEndCap: info.leading.leadingEndCap,
                    trailingEndCap: info.trailing.trailingEndCap,
                    screen: screen,
                    fullHeight: trailingFullHeight,
                    cornerRadiusFactor: fullConfiguration.cornerRadius
                )
            }
            let leadingPath = shapePath(
                in: leadingPathBounds,
                leadingEndCap: info.leading.leadingEndCap,
                trailingEndCap: info.leading.trailingEndCap,
                screen: screen,
                cornerRadiusFactor: fullConfiguration.cornerRadius
            )
            let trailingPath = shapePath(
                in: trailingPathBounds,
                leadingEndCap: info.trailing.leadingEndCap,
                trailingEndCap: info.trailing.trailingEndCap,
                screen: screen,
                fullHeight: trailingFullHeight,
                cornerRadiusFactor: fullConfiguration.cornerRadius
            )
            let path = NSBezierPath()
            path.append(leadingPath)
            path.append(trailingPath)
            return path
        }
        // Only one side is known (the other is still resolving, e.g. the
        // trailing width on macOS 26+ where the CGS menu-bar-item list comes
        // back empty until the AX rescan lands). Draw just the known pill so
        // the rest of the bar keeps showing the wallpaper instead of
        // collapsing to a full-width tint, which paints the transparent gap
        // gray and makes tint/wallpaper look swapped.
        if hasLeading {
            return shapePath(
                in: leadingPathBounds,
                leadingEndCap: info.leading.leadingEndCap,
                trailingEndCap: info.leading.trailingEndCap,
                screen: screen,
                cornerRadiusFactor: fullConfiguration.cornerRadius
            )
        }
        if hasTrailing {
            return shapePath(
                in: trailingPathBounds,
                leadingEndCap: info.trailing.leadingEndCap,
                trailingEndCap: info.trailing.trailingEndCap,
                screen: screen,
                fullHeight: trailingFullHeight,
                cornerRadiusFactor: fullConfiguration.cornerRadius
            )
        }
        // Nothing known yet: leave the whole bar as wallpaper.
        return NSBezierPath()
    }

    /// Returns the trailing width to draw for the display without blocking.
    /// Kicks off a background rescan when the cached value is stale; the view
    /// redisplays when the rescan completes.
    ///
    /// Never animates from inside `draw()` (that re-armed needsDisplay into a
    /// redraw storm): when the drawn width is off target, the display-synced
    /// driver glides it there.
    private func cachedTrailingStatusWidth(for display: CGDirectDisplayID) -> CGFloat {
        seedPredictionIfNeeded(for: display)
        refreshTrailingStatusWidth(for: display, force: false)
        let target = Self.trailingTarget(for: display)
        guard let current = Self.displayedTrailingWidth[display], current > 0 else {
            // First draw after boot/recreation: snap, never grow from 0.
            Self.setDisplayedTrailingWidth(target, for: display)
            return target
        }
        if current != target {
            startTrailingEaseIfNeeded()
        }
        return current
    }

    /// Starts the display-synced ease driver, unless already running.
    private func startTrailingEaseIfNeeded() {
        guard trailingEaseLink == nil else {
            return
        }
        let link = displayLink(target: self, selector: #selector(stepTrailingEase(_:)))
        // ProMotion: ask for the panel's full refresh rate.
        link.preferredFrameRateRange = CAFrameRateRange(minimum: 60, maximum: 120, preferred: 120)
        link.add(to: .main, forMode: .common)
        trailingEaseLink = link
        trailingEaseLastTimestamp = nil
    }

    /// Stops the ease driver.
    private func stopTrailingEase() {
        trailingEaseLink?.invalidate()
        trailingEaseLink = nil
        trailingEaseLastTimestamp = nil
    }

    /// Advances the ease one frame toward the current target.
    ///
    /// Exponential ease-out: each frame closes a time-based fraction of the
    /// remaining distance, so a target that moves mid-glide (a rescan
    /// correcting the prediction) bends the motion instead of restarting it.
    @objc private func stepTrailingEase(_ link: CADisplayLink) {
        guard let panel = overlayPanel else {
            stopTrailingEase()
            return
        }
        let display = panel.owningScreen.displayID
        let target = Self.trailingTarget(for: display)
        let current = Self.displayedTrailingWidth[display] ?? target
        let frameTime = link.targetTimestamp
        let elapsed = trailingEaseLastTimestamp.map { frameTime - $0 } ?? (link.targetTimestamp - link.timestamp)
        trailingEaseLastTimestamp = frameTime
        let timeConstant = target > current ? Self.trailingExpandTimeConstant : Self.trailingCollapseTimeConstant
        let fraction = 1 - exp(-min(max(elapsed, 0), 0.1) / timeConstant)
        var next = current + (target - current) * CGFloat(fraction)
        if abs(target - next) < 0.5 {
            next = target
        }
        Self.setDisplayedTrailingWidth(next, for: display)
        if next == target {
            stopTrailingEase()
        }
        needsDisplay = true
    }

    /// A control item moved or toggled: redraw now and keep chaining scans
    /// briefly so the rescans confirm (and correct) the prediction.
    private func noteControlItemMoved() {
        needsDisplay = true
        guard let panel = overlayPanel else {
            return
        }
        let display = panel.owningScreen.displayID
        Self.trailingBurstUntil[display] = Date().addingTimeInterval(1.5)
        let level = revealLevel()
        let previousLevel = Self.lastRevealLevel[display]
        if let level {
            Self.lastRevealLevel[display] = level
        }
        guard
            let level,
            let previousLevel,
            level != previousLevel
        else {
            // Not a toggle: the first publish after launch, a repeat publish
            // for a toggle already handled, or an icon/setting change.
            refreshTrailingStatusWidth(for: display, force: true)
            return
        }
        let predicted = predictedWidth(for: display, from: previousLevel, to: level)
        Logger.overlayPanel.debug("Toggle \(previousLevel) -> \(level): drawn=\(Self.displayedTrailingWidth[display] ?? -1) predicted=\(predicted ?? -1)")
        if let predicted {
            // Start gliding toward the destination with the icons, instead
            // of waiting ~1s for the AX rescan. Rescans that would measure
            // the slide mid-flight are held back until it lands.
            Self.toggleOriginWidth[display] = Self.trailingTarget(for: display)
            Self.setPredictiveTarget(predicted, for: display)
            Self.slideSettlesAt[display] = Date().addingTimeInterval(Self.slideDuration)
            needsDisplay = true
            refreshTrailingStatusWidth(for: display, force: true)
            return
        }
        // Destination never measured (first toggle into this level): let
        // every measurement through, starting with a quick local walk from
        // the drawn edge in the direction the icons move.
        Self.setPredictiveTarget(nil, for: display)
        Self.slideSettlesAt.removeValue(forKey: display)
        Self.toggleOriginWidth.removeValue(forKey: display)
        guard let current = Self.displayedTrailingWidth[display], current > 0 else {
            refreshTrailingStatusWidth(for: display, force: true)
            return
        }
        let edgeX = CGDisplayBounds(display).maxX - current
        let verdict: EdgeVerdict = level > previousLevel ? .added(hitX: edgeX) : .removed(edgeX: edgeX)
        refreshTrailingStatusWidth(for: display, force: true, quick: verdict)
    }

    /// Kicks off a background trailing-width rescan unless one is already in
    /// flight. Completions redisplay and, while a toggle burst is active,
    /// chain the next scan.
    ///
    /// - Parameter quick: when the edge check already knows which way the
    ///   cluster moved, re-measure locally first (~0.1s) so the pill tracks
    ///   hide/show instantly; the full sweep still runs right after to
    ///   confirm/correct via main-queue ordering.
    private func refreshTrailingStatusWidth(for display: CGDirectDisplayID, force: Bool, quick verdict: EdgeVerdict? = nil) {
        let cached = Self.trailingWidthCache[display]
        let isStale = force || cached.map { Date().timeIntervalSince($0.date) > Self.trailingWidthTTL } ?? true
        guard isStale else {
            return
        }
        if let settlesAt = Self.slideSettlesAt[display], settlesAt > Date() {
            // A predicted toggle's icons are still sliding: a sweep now would
            // only measure them mid-flight (and compete with the animation for
            // WindowServer). Measure once they rest.
            scheduleRefreshAfterSlide(for: display, at: settlesAt)
            return
        }
        guard !Self.trailingWidthScanInFlight.contains(display) else {
            // A sweep is already running, but the cheap local measure is
            // independent of it: skipping it here is what made the pill lag
            // behind the icons whenever a TTL scan happened to be in flight.
            if let verdict {
                applyQuickLeadingEdge(for: display, verdict: verdict)
            }
            return
        }
        Self.trailingWidthScanInFlight.insert(display)
        let levelAtStart = revealLevel()
        let startedAt = Date()
        // Never collapse to 0 while a stale-but-sane value exists: a
        // slightly wrong pill is far less jarring than a disappearing one.
        let previous = cached?.width ?? Self.settledWidth(for: display, level: levelAtStart) ?? 0
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            if let verdict {
                // Fast local re-measure ahead of the full sweep. Main-queue
                // FIFO applies this before the sweep's completion below.
                self?.applyQuickLeadingEdge(for: display, verdict: verdict)
            }
            let result = Self.trailingStatusWidthFallback(for: display)
            let width = result?.width ?? previous
            DispatchQueue.main.async { [weak self] in
                // Shared state first: the result survives even if this view
                // is gone (panel recreated mid-scan).
                Self.trailingWidthScanInFlight.remove(display)
                if let result {
                    Self.trailingFullBleed[display] = result.fullBleed
                    Self.screenCaptureActive = result.captureActive
                }
                if Self.isStripOccluded(display: display) {
                    // A dropdown/panel is over the bar: the scan saw the panel,
                    // not the icons. Drop it so neither the cache nor the settled
                    // widths learn the occluded value; the pill holds its width.
                    self?.needsDisplay = true
                    return
                }
                if let settlesAt = Self.slideSettlesAt[display], startedAt < settlesAt {
                    // Started before a predicted toggle's icons came to rest
                    // (it was already running when the toggle hit): a stale
                    // or mid-flight snapshot. Keep the prediction and measure
                    // again once they rest.
                    Logger.overlayPanel.debug("Scan dropped (mid-slide): measured=\(width) predictive=\(Self.predictiveTarget[display] ?? -1)")
                    self?.refreshTrailingStatusWidth(for: display, force: true)
                    return
                }
                let burstActive = Self.trailingBurstUntil[display].map { Date() < $0 } ?? false
                if
                    burstActive,
                    result != nil,
                    let origin = Self.toggleOriginWidth[display],
                    let predicted = Self.predictiveTarget[display],
                    abs(predicted - origin) > 20,
                    abs(width - origin) < abs(width - predicted)
                {
                    // AX still shows the pre-toggle layout. Hold the
                    // prediction and look again; once the burst ends the
                    // measurement wins regardless.
                    Logger.overlayPanel.debug("Scan dropped (stale): measured=\(width) origin=\(origin) predictive=\(predicted)")
                    self?.refreshTrailingStatusWidth(for: display, force: true)
                    return
                }
                if result != nil {
                    Self.toggleOriginWidth.removeValue(forKey: display)
                }
                Self.trailingWidthCache[display] = (width, Date())
                guard let self else {
                    return
                }
                self.needsDisplay = true
                Logger.overlayPanel.debug("Scan land: measured=\(width) drawn=\(Self.displayedTrailingWidth[display] ?? -1) predictive=\(Self.predictiveTarget[display] ?? -1) level=\(self.revealLevel().map { "\($0)" } ?? "?")")
                if result != nil {
                    // A real measurement outranks any prediction.
                    Self.setPredictiveTarget(nil, for: display)
                }
                if let until = Self.trailingBurstUntil[display], Date() < until {
                    self.refreshTrailingStatusWidth(for: display, force: true)
                } else {
                    Self.trailingBurstUntil.removeValue(forKey: display)
                    Self.slideSettlesAt.removeValue(forKey: display)
                    Self.toggleOriginWidth.removeValue(forKey: display)
                    // Burst settled: this is the real end position. Remember
                    // it for this level so the next toggle (and next launch)
                    // can predict instantly. Learn only from a real sweep (the
                    // `previous` fallback would re-learn the stale value it was
                    // supposed to correct), and only if no toggle happened
                    // while it ran.
                    if
                        width > 0,
                        result != nil,
                        let level = self.revealLevel(),
                        level == levelAtStart
                    {
                        Self.setSettledWidth(width, for: display, level: level)
                        Self.persistTrailingWidths()
                    }
                }
            }
        }
    }

    /// Runs one forced rescan for the display once the slide lands.
    ///
    /// Draws call `refreshTrailingStatusWidth` every frame while the pill
    /// glides, so pending requests are coalesced instead of piling up.
    private func scheduleRefreshAfterSlide(for display: CGDirectDisplayID, at date: Date) {
        guard Self.slideRefreshPending.insert(display).inserted else {
            return
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + max(0, date.timeIntervalSinceNow)) { [weak self] in
            Self.slideRefreshPending.remove(display)
            // Re-checks the window: a newer toggle may have pushed it out.
            self?.refreshTrailingStatusWidth(for: display, force: true)
        }
    }

    /// Whether a foreign window currently overlaps the menu bar strip.
    ///
    /// A dropdown/panel hanging over the bar corrupts AX width scans (probes
    /// hit the panel instead of the icons) and would retract the background
    /// mid-interaction. While occluded the pill may expand but its collapse is
    /// frozen; collapse resumes once focus leaves (panel closed). Steady state
    /// only ever shows the Menubar base and Ice's own overlay here, so both
    /// are excluded.
    private static func isStripOccluded(display: CGDirectDisplayID) -> Bool {
        let bounds = CGDisplayBounds(display)
        guard bounds.width > 0 else {
            return false
        }
        guard let screen = NSScreen.screens.first(where: { $0.displayID == display }) else {
            return false
        }
        let barHeight = screen.frame.maxY - screen.visibleFrame.maxY
        guard barHeight > 0 else {
            return false
        }
        let strip = CGRect(x: bounds.minX, y: bounds.minY, width: bounds.width, height: barHeight)
        let ownPID = NSRunningApplication.current.processIdentifier
        return WindowInfo.getOnScreenWindows(excludeDesktopWindows: true).contains { window in
            window.ownerPID != ownPID &&
            !window.isWindowServerWindow &&
            window.frame.intersects(strip)
        }
    }

    /// Whether an AX element at the given role/pid belongs to the trailing
    /// status cluster. App-menu items share the frontmost pid and are out.
    private static func isTrailingStatusElement(role: String?, pid: pid_t?, appMenuPid: pid_t?) -> Bool {
        // macOS 27 roles observed in the status cluster: AXGroup
        // (MenuBarAgent/ControlCenter), AXMenuBarItem, AXButton and AXImage
        // (third-party extras, screen-sharing/mirroring indicators).
        if role == "AXGroup" {
            return true
        }
        if role == "AXMenuBarItem" || role == "AXButton" || role == "AXImage" {
            return pid != nil && pid != appMenuPid
        }
        return false
    }

    /// Whether a bare `AXMenuBar` hit is really another app's status item.
    ///
    /// On a display whose menu bar isn't active, a third-party item reports
    /// its app's whole menu bar instead of an item: apps only know where their
    /// items sit on the active display. Read as empty bar, those items fell
    /// outside the pill there. Empty bar reports the menu bar of the app whose
    /// menus that display shows, so any other app's menu bar is one of its
    /// items. Ice's own is its blank spacer.
    private static func isOtherAppsMenuBar(pid: pid_t?, appMenuPid: pid_t?) -> Bool {
        guard let pid, let appMenuPid else {
            return false
        }
        return pid != appMenuPid && pid != ProcessInfo.processInfo.processIdentifier
    }

    /// Measures another app's item on an inactive display, whose element
    /// carries no usable frame, by probing outwards while the same app
    /// answers.
    private static func probedItemFrame(
        around x: CGFloat,
        y: Float,
        pid: pid_t?,
        displayBounds: CGRect
    ) -> CGRect? {
        func isSameItem(at probeX: CGFloat) -> Bool {
            guard
                probeX > displayBounds.minX,
                probeX < displayBounds.maxX,
                let element = try? systemWideElement.elementAtPosition(Float(probeX), y)
            else {
                return false
            }
            let role: String? = try? element.attribute("AXRole")
            return role == "AXMenuBar" && (try? element.pid()) == pid
        }
        // Icons are a few dozen points wide; 2pt steps, bounded either way.
        let step: CGFloat = 2
        let reach: CGFloat = 120
        var minX = x
        var maxX = x
        while minX - step > x - reach, isSameItem(at: minX - step) {
            minX -= step
        }
        while maxX + step < x + reach, isSameItem(at: maxX + step) {
            maxX += step
        }
        return CGRect(x: minX, y: displayBounds.minY + 4, width: maxX - minX + 1, height: 22)
    }

    /// Returns the frame of the status element at the given point, or `nil`
    /// when there is nothing status-like there.
    private static func statusFrameAt(
        x: CGFloat,
        y: Float,
        displayBounds: CGRect,
        appMenuPid: pid_t?
    ) -> CGRect? {
        guard let element = try? systemWideElement.elementAtPosition(Float(x), y) else {
            return nil
        }
        let role: String? = try? element.attribute("AXRole")
        let pid: pid_t? = try? element.pid()
        if role == "AXMenuBar" {
            guard isOtherAppsMenuBar(pid: pid, appMenuPid: appMenuPid) else {
                return nil
            }
            return probedItemFrame(around: x, y: y, pid: pid, displayBounds: displayBounds)
        }
        let frame: CGRect? = try? element.attribute("AXFrame")
        guard
            isTrailingStatusElement(role: role, pid: pid, appMenuPid: appMenuPid),
            let frame,
            frame.width > 0, frame.height > 0, frame.height <= 50,
            frame.minY <= displayBounds.origin.y + 10
        else {
            return nil
        }
        if let pid, pid == ProcessInfo.processInfo.processIdentifier, frame.width > 200 {
            // Ice's own control item: the expanded spacer that pushes a hidden
            // section offscreen is a 300–700pt placeholder, not a status icon.
            // Measuring it inflated the pill by ~110pt and kept it from ever
            // collapsing back after a toggle.
            return nil
        }
        return frame
    }

    /// Painted bounds (Quartz coordinates) of the on-screen Window Server
    /// `StatusIndicator` windows — the system share/record pill(s).
    ///
    /// That pill is WindowServer-drawn, so Accessibility can never see it:
    /// probing its paint returns the menubar behind it. Callers must union
    /// these bounds explicitly, or the whole purple pill sits outside the
    /// trailing pill on the wallpaper.
    ///
    /// Public CGWindowList read: owner/name/bounds need no extra entitlement.
    private static func screenCaptureIndicatorFrames() -> [CGRect] {
        guard let list = CGWindowListCopyWindowInfo(.optionOnScreenOnly, kCGNullWindowID) as? [[String: Any]] else {
            return []
        }
        return list.compactMap { info -> CGRect? in
            guard (info[kCGWindowOwnerName as String] as? String) == "Window Server",
                  (info[kCGWindowName as String] as? String) == "StatusIndicator",
                  let b = info[kCGWindowBounds as String] as? [String: Any],
                  let x = (b["X"] as? NSNumber)?.doubleValue,
                  let y = (b["Y"] as? NSNumber)?.doubleValue,
                  let w = (b["Width"] as? NSNumber)?.doubleValue,
                  let h = (b["Height"] as? NSNumber)?.doubleValue,
                  w > 0, h > 0
            else {
                return nil
            }
            return CGRect(x: x, y: y, width: w, height: h)
        }
    }

    /// The capture-indicator paint on the given display, if any.
    ///
    /// ALL matching windows, not the first: there can be several (share pill
    /// + recording dot), and list order is undefined — taking `.first` kept
    /// unioning the wrong one, so the blue pill intermittently sat outside.
    ///
    /// Sanity-checked (in the menu strip, pill-sized) so a stray window can
    /// never drag the trailing pill across the bar.
    private static func captureIndicatorFrames(for display: CGDirectDisplayID) -> [CGRect] {
        let bounds = CGDisplayBounds(display)
        guard bounds.width > 0 else {
            return []
        }
        return screenCaptureIndicatorFrames().filter { frame in
            frame.width < 300 &&
            frame.height <= 80 &&
            frame.minY <= bounds.minY + 12 &&
            frame.maxY >= bounds.minY &&
            frame.maxX > bounds.minX && frame.minX < bounds.maxX
        }
    }

    /// Returns whether Window Server currently owns a screen-capture
    /// `StatusIndicator` window — i.e. something is recording the screen.
    ///
    /// Public CGWindowList read: owner/name/layer need no extra entitlement.
    private static func hasScreenCaptureIndicator() -> Bool {
        !screenCaptureIndicatorFrames().isEmpty
    }

    /// Refines a coarse leftmost edge by sweeping the strip just left of it.
    ///
    /// The coarse 16pt single-row sweep can straddle a narrow glyph (or miss
    /// one whose hit area sits off the probed row, e.g. an active
    /// screen-sharing pill) and stop one icon too far right, leaving that
    /// icon floating off the pill. This bounded sweep (100pt, 8pt columns,
    /// three rows) catches the straggler. It stops after 24pt of empty strip
    /// so it can never jump the center gap into the application menu.
    ///
    /// Returns the refined edge plus the tallest status frame seen, so the
    /// caller can spot a full-bleed system pill (screen recording).
    private static func refineLeadingEdge(
        leftOf coarseX: CGFloat,
        displayBounds: CGRect,
        appMenuPid: pid_t?
    ) -> (x: CGFloat, maxHeight: CGFloat) {
        var leftmostX = coarseX
        var maxHeight: CGFloat = 0
        var consecutiveMisses = 0
        var x = coarseX - 8
        let stopX = max(displayBounds.minX, coarseX - 100)
        let rows: [Float] = [
            Float(displayBounds.origin.y + 10),
            Float(displayBounds.origin.y + 16),
            Float(displayBounds.origin.y + 22),
        ]
        while x > stopX, consecutiveMisses < 3 {
            var found: CGRect?
            for y in rows {
                if let frame = statusFrameAt(x: x, y: y, displayBounds: displayBounds, appMenuPid: appMenuPid) {
                    found = frame
                    break
                }
            }
            if let found {
                leftmostX = min(leftmostX, found.minX)
                maxHeight = max(maxHeight, found.height)
                consecutiveMisses = 0
                // Skip past the found element, like the coarse sweep.
                x = min(found.minX - 2, x - 8)
            } else {
                consecutiveMisses += 1
                x -= 8
            }
        }
        return (leftmostX, maxHeight)
    }

    /// What the fast edge check found.
    private enum EdgeVerdict {
        /// Drawn edge still matches the cluster.
        case valid
        /// Pill extends past the cluster (icons hidden/quit): the new
        /// leftmost is right of `edgeX`.
        case removed(edgeX: CGFloat)
        /// Status found at `hitX` left of the drawn edge (icons appeared).
        case added(hitX: CGFloat)
    }

    /// Verifies the currently drawn edge with a few AX probes: status just
    /// inside it, wallpaper just outside it.
    ///
    /// Returns what the edge looks like. Open menus covering the bar read as
    /// transient overlay and count as valid, so a menu never triggers a
    /// rescan war.
    private static func validateTrailingEdge(
        expectedWidth: CGFloat,
        displayBounds: CGRect,
        appMenuPid: pid_t?,
        indicators: [CGRect]
    ) -> EdgeVerdict {
        let edgeX = displayBounds.maxX - expectedWidth
        guard edgeX > displayBounds.minX + 20 else {
            // Nearly full bar — the full sweep owns this case.
            return .valid
        }
        let rows: [Float] = [
            Float(displayBounds.origin.y + 16),
            Float(displayBounds.origin.y + 10),
        ]
        var insideHit = false
        // Probe two depths: +6 lands on an icon for the normal 10pt pad,
        // but sits in the drawn overhang (no AX hit) under the 12pt
        // share/record-pill pad — +22 reaches the real AX frame there.
        outer: for dx: CGFloat in [6, 22] {
            let px = min(edgeX + dx, displayBounds.maxX - 2)
            for y in rows {
                // The system share/record paint is AX-invisible
                // (WindowServer-drawn): a probe landing on it reads as bare
                // menubar, so accept it as an inside hit explicitly instead
                // of rescanning forever.
                if indicators.contains(where: { $0.contains(CGPoint(x: px, y: CGFloat(y))) }) {
                    insideHit = true
                    break outer
                }
                guard let element = try? systemWideElement.elementAtPosition(
                    Float(px),
                    y
                ) else {
                    continue
                }
                let role: String? = try? element.attribute("AXRole")
                if role == "AXMenu" || role == "AXMenuItem" {
                    return .valid
                }
                let pid: pid_t? = try? element.pid()
                if role == "AXMenuBar" {
                    // Another app's item on an inactive display.
                    if isOtherAppsMenuBar(pid: pid, appMenuPid: appMenuPid) {
                        insideHit = true
                        break outer
                    }
                    continue
                }
                guard isTrailingStatusElement(role: role, pid: pid, appMenuPid: appMenuPid) else {
                    continue
                }
                let frame: CGRect? = try? element.attribute("AXFrame")
                if
                    let frame,
                    frame.width > 0, frame.height > 0, frame.height <= 50,
                    frame.minY <= displayBounds.origin.y + 10
                {
                    insideHit = true
                    break outer
                }
            }
        }
        guard insideHit else {
            return .removed(edgeX: edgeX)
        }
        // Outside must be empty. New system indicators (mic mode, share pill,
        // a fresh recorder icon) can pop in well left of the drawn edge, so
        // sweep a coarse lookahead out to ~140pt: one hit anywhere out there
        // means the edge is stale. Steady state pays ~12 cheap probes per
        // tick and bails on the first hit.
        for dx: CGFloat in [16, 40, 64, 88, 112, 136] {
            let ox = edgeX - dx
            if ox <= displayBounds.minX {
                break
            }
            for y in rows where statusFrameAt(x: ox, y: y, displayBounds: displayBounds, appMenuPid: appMenuPid) != nil {
                return .added(hitX: ox)
            }
        }
        return .valid
    }

    /// Fast-path edge check; runs on a timer and on app launch/terminate.
    ///
    /// On mismatch it kicks a short burst + forced rescan so the pill heals
    /// in ~1s. On match it just touches the cache timestamp, which also keeps
    /// the draw-path backstop from firing redundant full sweeps — steady
    /// state costs ~50 cheap AX probes/s instead of a full sweep every TTL.
    private func checkTrailingEdge() {
        guard
            let panel = overlayPanel,
            let appState = panel.appState,
            !appState.isPreview,
            !appState.menuBarManager.isMenuBarHiddenBySystem,
            !appState.isActiveSpaceFullscreen
        else {
            return
        }
        let display = panel.owningScreen.displayID
        guard
            !Self.trailingWidthScanInFlight.contains(display),
            Self.trailingBurstUntil[display].map({ Date() >= $0 }) ?? true
        else {
            // A scan or toggle burst already owns the edge.
            return
        }
        let displayBounds = CGDisplayBounds(display)
        guard displayBounds.width > 0 else {
            return
        }
        let expected = Self.predictiveTarget[display]
            ?? Self.trailingWidthCache[display]?.width
            ?? Self.settledWidth(for: display, level: revealLevel())
            ?? 0
        guard expected > 0 else {
            refreshTrailingStatusWidth(for: display, force: false)
            return
        }
        let y = Float(displayBounds.origin.y + 16)
        let appMenuPid: pid_t? = try? systemWideElement.elementAtPosition(
            Float(displayBounds.origin.x + 2),
            y
        )?.pid()
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            let indicators = Self.captureIndicatorFrames(for: display)
            let verdict = Self.validateTrailingEdge(
                expectedWidth: expected,
                displayBounds: displayBounds,
                appMenuPid: appMenuPid,
                indicators: indicators
            )
            // Cheap capture-indicator poll (public window list, no AX):
            // flips the extra pad + full height on/off within ~0.5s of a
            // recording starting/stopping, on every OS path.
            let captureActive = Self.hasScreenCaptureIndicator()
            DispatchQueue.main.async { [weak self] in
                guard let self else {
                    return
                }
                if captureActive != Self.screenCaptureActive {
                    Self.screenCaptureActive = captureActive
                    self.needsDisplay = true
                    if captureActive {
                        // A share/record just started: grow the pill over the
                        // system paint NOW from the window list (~0.1s) instead
                        // of waiting a full AX sweep. Only ever expands, so it
                        // can't flicker; the sweep below confirms/corrects.
                        if let grown = Self.expandedWidthForIndicators(
                            for: display,
                            indicators: indicators,
                            currentWidth: expected
                        ) {
                            Self.trailingWidthCache[display] = (grown, Date())
                            Self.setPredictiveTarget(grown, for: display)
                        }
                    }
                    self.refreshTrailingStatusWidth(for: display, force: true)
                }
                if case .valid = verdict {
                    if Self.trailingWidthCache[display] != nil {
                        Self.trailingWidthCache[display]?.date = Date()
                    }
                } else if !Self.isStripOccluded(display: display) {
                    Logger.overlayPanel.debug("Edge check \(display): expected=\(expected) verdict=\(verdict)")
                    Self.trailingBurstUntil[display] = Date().addingTimeInterval(1.0)
                    self.needsDisplay = true
                    self.refreshTrailingStatusWidth(for: display, force: true, quick: verdict)
                }
                // Else: a dropdown/panel is over the bar — hold the pill until
                // it leaves instead of rescanning toward the occluded width.
            }
        }
    }

    /// Grows the trailing width to cover freshly appeared system paint.
    ///
    /// Pure window-list measurement (no AX): returns `nil` when nothing needs
    /// to grow, so callers only ever expand and can never cause a flicker.
    private static func expandedWidthForIndicators(
        for display: CGDirectDisplayID,
        indicators: [CGRect],
        currentWidth: CGFloat
    ) -> CGFloat? {
        let displayBounds = CGDisplayBounds(display)
        guard displayBounds.width > 0, !indicators.isEmpty else {
            return nil
        }
        let edgeX = displayBounds.maxX - currentWidth
        var axLeft = edgeX
        for indicator in indicators where indicator.maxX >= axLeft - 80 {
            axLeft = min(axLeft, indicator.minX - 3)
        }
        guard axLeft < edgeX else {
            return nil
        }
        let width = displayBounds.maxX - max(displayBounds.minX, axLeft - 12)
        let scanWindow = min(displayBounds.width, 1100)
        guard width > currentWidth, width < scanWindow - 10 else {
            return nil
        }
        return width
    }

    /// Re-measures the cluster edge locally around the last drawn edge.
    ///
    /// A full sweep costs hundreds of AX round-trips — seconds under Window
    /// Server contention while capturing. But hide/show damage is always
    /// local to the old edge: step right to find the new leftmost after a
    /// removal, or left from the first outside hit after an addition.
    /// ~20 probes, ~0.1s. Returns a ready-to-display width, or `nil` when the
    /// local picture is ambiguous (the full sweep then decides alone — a
    /// brief tongue beats a vanish-flicker).
    private static func quickLeadingEdgeWidth(
        for display: CGDirectDisplayID,
        verdict: EdgeVerdict
    ) -> CGFloat? {
        let displayBounds = CGDisplayBounds(display)
        guard displayBounds.width > 0 else {
            return nil
        }
        let y = Float(displayBounds.origin.y + 16)
        let appMenuPid: pid_t? = try? systemWideElement.elementAtPosition(
            Float(displayBounds.origin.x + 2),
            y
        )?.pid()
        let rows: [Float] = [
            Float(displayBounds.origin.y + 16),
            Float(displayBounds.origin.y + 10),
        ]
        var axLeft: CGFloat?
        switch verdict {
        case .valid:
            return nil
        case .removed(let edgeX):
            var x = edgeX + 8
            let stopX = min(displayBounds.maxX - 2, edgeX + 400)
            while x < stopX {
                var found: CGRect?
                for row in rows {
                    if let frame = statusFrameAt(x: x, y: row, displayBounds: displayBounds, appMenuPid: appMenuPid) {
                        found = frame
                        break
                    }
                }
                if let found {
                    axLeft = found.minX
                    break
                }
                x += 16
            }
            guard axLeft != nil else {
                return nil
            }
        case .added(let hitX):
            var x = hitX - 8
            let stopX = max(displayBounds.minX, hitX - 200)
            var misses = 0
            var minX = hitX
            // ponytail: a walk that never hit anything must not return — the
            // starting guess would read as a ~15pt wider pill that the sweep
            // then snaps back, i.e. a visible breath right after every toggle.
            var sawHit = false
            while x > stopX, misses < 3 {
                var found: CGRect?
                for row in rows {
                    if let frame = statusFrameAt(x: x, y: row, displayBounds: displayBounds, appMenuPid: appMenuPid) {
                        found = frame
                        break
                    }
                }
                if let found {
                    sawHit = true
                    minX = min(minX, found.minX)
                    misses = 0
                    x = min(found.minX - 2, x - 8)
                } else {
                    misses += 1
                    x -= 16
                }
            }
            guard sawHit else {
                return nil
            }
            axLeft = minX
        }
        guard var axLeft else {
            return nil
        }
        // Same tail as the full sweep: union the AX-invisible system paint,
        // then pad.
        let indicators = captureIndicatorFrames(for: display)
        for indicator in indicators where indicator.maxX >= axLeft - 80 {
            axLeft = min(axLeft, indicator.minX - 3)
        }
        // ponytail: half the original 10/12pt pad — a full pad left a blank
        // strip before the leftmost icon, zero hugged the frame so tight the
        // pill looked clipped. 5 keeps a small, even inset on both ends.
        let pad: CGFloat = (!indicators.isEmpty || hasScreenCaptureIndicator()) ? 4 : 3
        let leftmostX = max(displayBounds.minX, axLeft - pad)
        let width = displayBounds.maxX - leftmostX
        let scanWindow = min(displayBounds.width, 1100)
        guard width > 0, width < scanWindow - 10 else {
            return nil
        }
        return width
    }

    /// Estimates the width of the trailing status-item cluster using Accessibility.
    ///
    /// On macOS 27, `CGSGetProcessMenuBarWindowList` returns only the Menubar
    /// itself, so `MenuBarItem.getMenuBarItems` comes back empty and split
    /// shapes collapse to full. This scans the top strip from right to left
    /// and returns the distance from the right edge to the leftmost status
    /// element. Returns `nil` when nothing status-like is found.
    ///
    /// - ponytail: O(n) AX scan per call; always call via cachedTrailingStatusWidth
    ///   (background + TTL), never directly from draw.
    private static func trailingStatusWidthFallback(for display: CGDirectDisplayID) -> (width: CGFloat, fullBleed: Bool, captureActive: Bool)? {
        let displayBounds = CGDisplayBounds(display)
        guard displayBounds.width > 0 else {
            return nil
        }
        let y = Float(displayBounds.origin.y + 16)
        // Middle of the (now 33pt on macOS 27) bar hits items reliably;
        // the top edge can return the WindowManager glass container instead.
        let appMenuPid: pid_t? = (try? systemWideElement.elementAtPosition(
            Float(displayBounds.origin.x + 2),
            y
        )?.pid())

        var leftmostX: CGFloat?
        var maxHeight: CGFloat = 0
        // Status cluster lives at the right edge; 1100pt covers even wide
        // clusters (date + Control Center + a dozen icons pushes past 800).
        // Scan the whole window: some third-party items report their parent
        // AXMenuBar instead of a button, so early-exit on gaps stops too soon.
        // Step 16pt stays below the narrowest icon (~20pt) so nothing is
        // skipped, but cuts AX round-trips ~40% vs 10pt — the scan, not the
        // animation, was the ~1s lag behind the icons. A bounded fine sweep
        // below fixes up whatever the coarse step straddles.
        let step: CGFloat = 16
        var x = displayBounds.maxX - 2
        let stopX = max(displayBounds.minX, displayBounds.maxX - 1100)
        while x > stopX {
            guard let frame = statusFrameAt(x: x, y: y, displayBounds: displayBounds, appMenuPid: appMenuPid) else {
                x -= step
                continue
            }
            leftmostX = min(leftmostX ?? frame.minX, frame.minX)
            maxHeight = max(maxHeight, frame.height)
            // Skip past this element to cut down on AX calls.
            // min() guarantees progress when the frame edge lands on x.
            x = min(frame.minX - 2, x - step)
            continue
        }
        guard let coarseX = leftmostX else {
            return nil
        }
        // Fine sweep for a narrow/off-row straggler left of the coarse edge
        // (e.g. an active screen-sharing pill), then pad left so the pill
        // tucks under the leading icon.
        let refined = refineLeadingEdge(leftOf: coarseX, displayBounds: displayBounds, appMenuPid: appMenuPid)
        maxHeight = max(maxHeight, refined.maxHeight)
        // A full-bleed system pill (screen sharing/recording) draws taller than a
        // normal icon: go full height (see shapePath). Its wider system paint is
        // unioned in below via `captureIndicatorFrames`.
        let barHeight = NSScreen.screens.first(where: { $0.displayID == display })?.getMenuBarHeight() ?? 26
        let fullBleed = maxHeight >= barHeight - 4
        let captureActive = hasScreenCaptureIndicator()
        let pad: CGFloat = (fullBleed || captureActive) ? 4 : 3
        var axLeft = refined.x
        // The system share/record paint is WindowServer-drawn and AX-invisible,
        // so the sweep above always anchors at its right-hand neighbour.
        // Union every painted indicator explicitly (3pt margin), or a purple
        // pill sits outside the trailing pill. The 80pt tolerance keeps a
        // stray window from dragging the pill across the bar.
        let indicators = captureIndicatorFrames(for: display)
        for indicator in indicators where indicator.maxX >= axLeft - 80 {
            axLeft = min(axLeft, indicator.minX - 3)
        }
        leftmostX = max(displayBounds.minX, axLeft - pad)
        guard let leftmostX else {
            return nil
        }
        let width = displayBounds.maxX - leftmostX
        guard width > 0 else {
            return nil
        }
        // The sweep only covers the trailing 1100pt. A width pinned at that
        // cap means the scan swallowed a glass container (or a cluster wider
        // than the scan window) — treat it as unknown so split doesn't paint
        // an over-wide pill over the transparent gap.
        let scanWindow = min(displayBounds.width, 1100)
        guard width < scanWindow - 10 else {
            return nil
        }
        Logger.overlayPanel.debug("Trailing scan: coarse=\(coarseX) refined=\(refined.x) axLeft=\(axLeft) width=\(width) fullBleed=\(fullBleed) capture=\(captureActive) indicators=\(indicators)")
        return (width, fullBleed, captureActive)
    }

    /// Returns the bounds that the view's drawn content can occupy.
    private func getDrawableBounds() -> CGRect {
        return CGRect(
            x: bounds.origin.x,
            y: bounds.origin.y + 5,
            width: bounds.width,
            height: bounds.height - 5
        )
    }

    /// Syncs the blur and tint layers with the given shape.
    private func updateChrome(with shapePath: NSBezierPath, fillRect: CGRect, shapeKind: MenuBarShapeKind) {
        if blurView.frame != bounds {
            blurView.frame = bounds
        }
        if tintView.frame != bounds {
            tintView.frame = bounds
        }
        let isEmpty = shapePath.isEmpty
        // Blur only matters when enabled and visible through the tint.
        // NSVisualEffectView has no radius API, so the amount drives the
        // layer opacity: it fades between fully blurred and the sharp live
        // background, which reads as blur strength.
        blurView.isHidden = configuration.blurAmount <= 0
            || isEmpty
            || (configuration.tintKind != .none && configuration.tintOpacity >= 1)
        blurView.alphaValue = configuration.blurAmount
        // The mask is a standalone layer, so Core Animation would give each
        // change an implicit 0.25s animation: the blur edge trailed the tint
        // edge on every toggle. The glide is already driven frame by frame.
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        blurMask.frame = blurView.bounds
        blurMask.path = shapePath.cgPath
        CATransaction.commit()
        tintView.shapePath = shapePath
        tintView.fillRect = fillRect
        tintView.shapeKind = shapeKind
        tintView.tintKind = configuration.tintKind
        tintView.tintColor = configuration.tintColor
        tintView.tintGradient = configuration.tintGradient
        tintView.tintOpacity = configuration.tintOpacity
        tintView.hasBorder = configuration.hasBorder
        tintView.borderColor = configuration.borderColor
        tintView.borderWidth = configuration.borderWidth
        tintView.isHidden = isEmpty || (configuration.tintKind == .none && !configuration.hasBorder)
        tintView.needsDisplay = true
    }

    override func draw(_ dirtyRect: NSRect) {
        guard
            let overlayPanel,
            let context = NSGraphicsContext.current
        else {
            return
        }

        let drawableBounds = getDrawableBounds()

        let shapePath = switch fullConfiguration.shapeKind {
        case .none:
            NSBezierPath(rect: drawableBounds)
        case .full:
            pathForFullShape(
                in: drawableBounds,
                info: fullConfiguration.fullShapeInfo,
                isInset: fullConfiguration.isInset,
                screen: overlayPanel.owningScreen
            )
        case .split:
            pathForSplitShape(
                in: drawableBounds,
                info: fullConfiguration.splitShapeInfo,
                isInset: fullConfiguration.isInset,
                screen: overlayPanel.owningScreen
            )
        }

        switch fullConfiguration.shapeKind {
        case .none:
            if configuration.hasShadow {
                let gradient = NSGradient(
                    colors: [
                        NSColor(white: 0.0, alpha: 0.0),
                        NSColor(white: 0.0, alpha: 0.2),
                    ]
                )
                let shadowBounds = CGRect(
                    x: bounds.minX,
                    y: bounds.minY,
                    width: bounds.width,
                    height: 5
                )
                gradient?.draw(in: shadowBounds, angle: 90)
            }
        case .full, .split:
            // Nothing is drawn outside the shape: the panel is transparent
            // there, so the live background shows through.
            if configuration.hasShadow {
                context.saveGraphicsState()
                defer {
                    context.restoreGraphicsState()
                }

                let shadowClipPath = NSBezierPath(rect: bounds)
                shadowClipPath.append(shapePath.reversed)
                shadowClipPath.setClip()

                shapePath.drawShadow(color: .black.withAlphaComponent(0.5), radius: 5)
            }
        }

        // Tint and border live in layers above the blur; sync them here.
        updateChrome(with: shapePath, fillRect: drawableBounds, shapeKind: fullConfiguration.shapeKind)
    }
}

// MARK: - Tint View

/// Draws the pill tint (and border) above the blur layer.
private final class MenuBarTintView: NSView {
    var shapePath = NSBezierPath()
    var fillRect = CGRect.zero
    var shapeKind = MenuBarShapeKind.none
    var tintKind = MenuBarTintKind.none
    var tintColor: CGColor = NSColor.black.cgColor
    var tintGradient = CustomGradient.defaultMenuBarTint
    var tintOpacity = 1.0
    var hasBorder = false
    var borderColor: CGColor = NSColor.black.cgColor
    var borderWidth = 1.0

    override func draw(_ dirtyRect: NSRect) {
        guard
            !shapePath.isEmpty,
            let context = NSGraphicsContext.current
        else {
            return
        }

        context.saveGraphicsState()
        shapePath.setClip()

        switch tintKind {
        case .none:
            break
        case .solid:
            if let tintColor = NSColor(cgColor: tintColor)?.withAlphaComponent(tintOpacity) {
                tintColor.setFill()
                fillRect.fill()
            }
        case .gradient:
            if let tintGradient = tintGradient.withAlphaComponent(tintOpacity).nsGradient {
                tintGradient.draw(in: fillRect, angle: 0)
            }
        }

        context.restoreGraphicsState()

        if hasBorder {
            switch shapeKind {
            case .none:
                let borderBounds = CGRect(
                    x: bounds.minX,
                    y: bounds.minY + 5,
                    width: bounds.width,
                    height: borderWidth
                )
                NSColor(cgColor: borderColor)?.setFill()
                NSBezierPath(rect: borderBounds).fill()
            case .full, .split:
                guard let borderColor = NSColor(cgColor: borderColor) else {
                    return
                }
                context.saveGraphicsState()
                defer {
                    context.restoreGraphicsState()
                }

                // HACK: Insetting a path to get an "inside" stroke is surprisingly
                // difficult. We can fake the correct line width by doubling it, as
                // anything outside the shape path will be clipped.
                shapePath.lineWidth = borderWidth * 2
                shapePath.setClip()

                borderColor.setStroke()
                shapePath.stroke()
            }
        }
    }
}

// MARK: - Logger
private extension Logger {
    static let overlayPanel = Logger(category: "MenuBarOverlayPanel")
}
