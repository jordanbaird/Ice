//
//  Concealer27.swift
//  Ice
//

import Cocoa
import Combine
import OSLog

/// Hides menu bar items on macOS 27, where Ice's expanding dividers no longer work.
///
/// On macOS 27 the section of each application comes from a saved layout, first
/// taken from the user's Ice layout: MenuBarAgent reorders items on its own, so their
/// order on the bar no longer says which section they belong to. The concealer hides
/// applications through `MenuBarAssessmentAssertion27`, following that layout and the
/// state of Ice's sections.
@available(macOS 27.0, *)
@MainActor
final class Concealer27 {
    private let controller = ConcealmentController27(backend: MenuBarAssessmentAssertion27())
    private let logger = Logger(category: "Concealer27")
    private weak var appState: AppState?
    private var observers = [NSObjectProtocol]()
    private var applyTask: Task<Void, Never>?
    private var suspendedUntil: ContinuousClock.Instant?

    /// When concealment last changed, which is when the bar last started moving.
    private var lastChangeAt = ContinuousClock.now

    /// How long MenuBarAgent animates the bar after items are concealed or released
    /// (measured on macOS 27.0: about 250 ms, with a margin here).
    private static let settleAfterChange = Duration.milliseconds(400)

    /// Applications shown for a moment, with the number of callers showing each.
    private var temporarilyShown = [String: Int]()
    private var cancellables = Set<AnyCancellable>()

    /// Whether any application is meant to be concealed right now.
    private(set) var isConcealing = false

    /// Process identifiers of the applications meant to be concealed right now.
    private(set) var concealedPIDs = Set<pid_t>()

    /// The section of each application. Applications missing from it are visible.
    private var savedLayout: [String: MacOS27Section] {
        let stored = Defaults.dictionary(forKey: .macOS27Layout) as? [String: Int] ?? [:]
        return stored.compactMapValues(MacOS27Section.init(rawValue:))
    }

    func performSetup(with appState: AppState) {
        self.appState = appState
        guard MenuBarAssessmentAssertion27.isAvailable else {
            logger.error("MenuBarClientCore assertions are unavailable, so items will not be hidden")
            return
        }
        // Every assertion is an allowlist of the applications running when it was made, so an
        // application missing from it has its items hidden. The workspace's launch notification
        // is never posted for agents (`LSUIElement`), which is what most menu bar applications
        // are, including the ones macOS starts on demand for recording and screen sharing: their
        // items stayed hidden until something else happened to update the concealment. The
        // running applications are observed instead, which covers agents as well.
        NSWorkspace.shared.publisher(for: \.runningApplications)
            .map { Set($0.compactMap(\.bundleIdentifier)) }
            .removeDuplicates()
            .dropFirst()
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                MainActor.assumeIsolated {
                    self?.update()
                }
            }
            .store(in: &cancellables)
        observers.append(NotificationCenter.default.addObserver(
            forName: NSApplication.willTerminateNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.controller.releaseAll()
            }
        })
        // Entering or leaving fullscreen swaps the menu bar the items are drawn in, and nothing
        // else here notices: the concealment was left exactly as the previous bar had it, so
        // Ice's own item was missing from the bar that slides down over a fullscreen window and
        // there was nothing to click. `HIDEventManager` watches the same publisher, for the same
        // reason, on earlier versions of macOS.
        appState.$activeSpace
            .map(\.isFullscreen)
            .removeDuplicates()
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                MainActor.assumeIsolated {
                    self?.update()
                }
            }
            .store(in: &cancellables)
        let navigation = appState.navigationState
        navigation.$isSettingsPresented
            .combineLatest(navigation.$settingsNavigationIdentifier)
            .removeDuplicates { $0.0 == $1.0 && $0.1 == $1.1 }
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                MainActor.assumeIsolated {
                    self?.update()
                }
            }
            .store(in: &cancellables)
        update()
    }

    /// Derives what to conceal from Ice's sections and applies it.
    func update() {
        guard let appState, MenuBarAssessmentAssertion27.isAvailable else {
            return
        }
        if let suspendedUntil, ContinuousClock.now < suspendedUntil {
            return
        }
        let applications = NSWorkspace.shared.runningApplications
        let running = Set(applications.compactMap(\.bundleIdentifier))
        let layout = SectionLayout27.effectiveLayout(observed: [:], saved: savedLayout, running: running)
        let target = ConcealmentPlanner27.concealedSets(
            layout: layout,
            state: revealState(appState),
            temporarilyShown: Set(temporarilyShown.keys)
        )
        let concealed = ConcealmentPlanner27.effectivelyConcealed(sets: target)
        isConcealing = !target.isEmpty
        defer { MenuBarItemProvider27.setConcealedPIDs(concealedPIDs) }
        concealedPIDs = Set(applications.compactMap { application in
            guard let bundleID = application.bundleIdentifier, concealed.contains(bundleID) else {
                return nil
            }
            return application.processIdentifier
        })
        lastChangeAt = .now
        updateGeneration += 1
        let generation = updateGeneration
        let previous = applyTask
        let task = Task { [weak self, controller, logger] in
            await previous?.value
            // Applies follow one another, so a burst of updates queued one apply behind the
            // other, each laying the bar out again. Only the latest target is worth applying,
            // as it comes later in the queue. Releases are never skipped, so applies and
            // releases still land in the order they were asked for.
            guard let self, updateGeneration == generation else {
                return
            }
            do {
                try await controller.apply(target: target, running: running)
            } catch {
                logger.error("Could not apply concealment: \(error, privacy: .public)")
            }
        }
        applyTask = task
        // Concealing moves the remaining items, and hover hit-testing uses their cached
        // frames. The refresh stays out of `applyTask`, so a slow read never holds up the
        // next change. The bar animates for about 250 ms (measured). Only the refresh after
        // the latest update runs, as each one reads every application's items.
        Task { [weak self] in
            await task.value
            try? await Task.sleep(for: .milliseconds(400))
            guard let self, updateGeneration == generation else {
                return
            }
            await self.appState?.itemManager.cacheItemsIfNeeded()
            await logStuckOverflowIfNeeded()
        }
    }

    /// Counts the updates made, so an update overtaken by a later one is skipped.
    private var updateGeneration = 0

    /// Releases every assertion for a moment, so a click can reach a system item.
    func suspend(for duration: Duration) {
        lastChangeAt = .now
        suspendedUntil = .now + duration
        isConcealing = false
        concealedPIDs.removeAll()
        let previous = applyTask
        applyTask = Task { [controller] in
            await previous?.value
            controller.releaseAll()
        }
        Task { [weak self] in
            try? await Task.sleep(for: duration)
            self?.suspendedUntil = nil
            self?.update()
        }
    }

    /// Releases every assertion and returns once that has actually happened.
    ///
    /// Releasing goes through MenuBarAgent and queues behind whatever concealment change came
    /// before it. A click replayed on a timer could therefore arrive while the assertion was
    /// still live, and MenuBarAgent ignores those — which is why a click on the clock sometimes
    /// did nothing and worked on the second try.
    func suspendReleased(for duration: Duration) async {
        lastChangeAt = .now
        suspendedUntil = .now + duration
        isConcealing = false
        concealedPIDs.removeAll()
        let previous = applyTask
        let release = Task { [controller] in
            await previous?.value
            controller.releaseAll()
        }
        applyTask = release
        await release.value
        Task { [weak self] in
            try? await Task.sleep(for: duration)
            self?.suspendedUntil = nil
            self?.update()
        }
    }

    /// Puts concealment back before the suspension would have run out.
    func endSuspension() {
        guard suspendedUntil != nil else {
            return
        }
        suspendedUntil = nil
        update()
    }

    /// How much of the bar's movement is still to come after the last concealment change.
    ///
    /// Work that runs while MenuBarAgent animates the bar lands on top of that animation:
    /// revealing the hidden items set off four overlapping display captures of 260–290 ms
    /// each and six Accessibility sweeps in little over a second (measured 2026-09-16), and
    /// the animation stuttered. Heavy work waits this out.
    func timeUntilSettled() -> Duration? {
        let settleAt = lastChangeAt + Self.settleAfterChange
        let now = ContinuousClock.now
        return now < settleAt ? settleAt - now : nil
    }

    /// Shows applications for a moment, to click or photograph their items.
    /// Every call must be balanced by ``endTemporaryShow(bundleIDs:)``.
    ///
    /// The whole set is shown in one change. Shown one at a time, each call re-applied
    /// concealment and MenuBarAgent animated the bar again, so photographing ten items meant
    /// ten reflows in a row and the capture caught the items in mid-fade: a faint glyph in a
    /// wide haze of bar that the background removal could not account for (measured
    /// 2026-09-17: those tiles held 1.6–2.3 % opaque pixels against 21–26 % faint ones, where
    /// an item photographed while it stood still holds 5–20 % against 3–9 %).
    func showTemporarily(bundleIDs: some Collection<String>) {
        guard !bundleIDs.isEmpty else {
            return
        }
        for bundleID in bundleIDs {
            temporarilyShown[bundleID, default: 0] += 1
        }
        update()
    }

    /// Ends one ``showTemporarily(bundleIDs:)``.
    func endTemporaryShow(bundleIDs: some Collection<String>) {
        guard !bundleIDs.isEmpty else {
            return
        }
        for bundleID in bundleIDs {
            guard let count = temporarilyShown[bundleID] else {
                continue
            }
            temporarilyShown[bundleID] = count > 1 ? count - 1 : nil
        }
        update()
    }

    /// Shows an application for a moment, to click or photograph its item.
    /// Every call must be balanced by ``endTemporaryShow(bundleID:)``.
    func showTemporarily(bundleID: String) {
        showTemporarily(bundleIDs: CollectionOfOne(bundleID))
    }

    /// Ends one ``showTemporarily(bundleID:)``.
    func endTemporaryShow(bundleID: String) {
        endTemporaryShow(bundleIDs: CollectionOfOne(bundleID))
    }

    /// Moves an application to a section of the saved layout and applies it.
    func setSection(_ section: MacOS27Section, for bundleID: String) {
        let updated = SectionLayout27.settingSection(section, for: bundleID, in: savedLayout)
        Defaults.set(updated.mapValues(\.rawValue), forKey: .macOS27Layout)
        update()
        Task { [weak self] in
            await self?.appState?.itemManager.cacheItemsRegardless()
        }
    }

    /// Builds the item cache from the saved layout rather than the order on the bar.
    func cacheFromSavedLayout(items: [MenuBarItem], displayID: CGDirectDisplayID?) -> MenuBarItemManager.ItemCache {
        var cache = MenuBarItemManager.ItemCache(displayID: displayID)
        let layout = savedLayout
        let bundleIDs = MenuBarItem.sourceBundleIDs(of: items)
        for item in items.sorted(by: { $0.bounds.minX < $1.bounds.minX }) where item.canBeHidden && !item.isSystemClone {
            if item.isControlItem {
                if item.tag == .visibleControlItem {
                    cache[.visible].append(item)
                }
                continue
            }
            switch layout[item.sourcePID.flatMap { bundleIDs[$0] } ?? ""] ?? .visible {
            case .visible: cache[.visible].append(item)
            case .hidden: cache[.hidden].append(item)
            case .alwaysHidden: cache[.alwaysHidden].append(item)
            }
        }
        return cache
    }

    // MARK: Private

    /// When a stuck overflow was last logged.
    private var lastStuckLogAt: ContinuousClock.Instant?

    /// Logs when concealment seems to have left the notched bar's items folded with no
    /// overflow button (see `StuckOverflow27`).
    ///
    /// Nothing is done about it yet. Accessibility keeps the frames of items that are no longer
    /// drawn, so the check can mistake one of those for a folded item; acting on it would make the
    /// bar lay itself out again for nothing. The log shows whether the check holds up the next
    /// time the state turns up (see `Scripts/macos27/reflow-probe.swift`).
    private func logStuckOverflowIfNeeded() async {
        guard
            let screen = NSScreen.screenWithActiveMenuBar,
            screen.hasNotch,
            isStuckOverflow(on: screen, items: await MenuBarItemProvider27.items())
        else {
            return
        }
        if let lastStuckLogAt, ContinuousClock.now - lastStuckLogAt < .seconds(10) {
            return
        }
        lastStuckLogAt = .now
        logger.notice("Notched bar looks stuck with folded items and no overflow button")
    }

    private func isStuckOverflow(on screen: NSScreen, items: [MenuBarItem]) -> Bool {
        let displayBounds = CGDisplayBounds(screen.displayID)
        let ownPID = ProcessInfo.processInfo.processIdentifier
        let frames = items
            .filter { !concealedPIDs.contains($0.ownerPID) && $0.ownerPID != ownPID && displayBounds.intersects($0.bounds) }
            .map(\.bounds)
        let notch = StuckOverflow27.notchSpan(
            displayBounds: displayBounds,
            leftAreaWidth: screen.auxiliaryTopLeftArea?.width,
            rightAreaWidth: screen.auxiliaryTopRightArea?.width
        )
        return StuckOverflow27.isStuck(
            visibleItemFrames: frames,
            chevronFrame: MenuBarItemProvider27.overflowButtonFrame(),
            notchSpan: notch
        )
    }

    private func revealState(_ appState: AppState) -> RevealState27 {
        let navigation = appState.navigationState
        if navigation.isSettingsPresented, navigation.settingsNavigationIdentifier == .menuBarLayout {
            // Everything is drawn while the layout window is open, so every item can be photographed.
            return .allRevealed
        }
        if appState.settings.general.useIceBar {
            // The Ice Bar shows hidden items in its own panel, so the bar stays concealed.
            return .allHidden
        }
        let manager = appState.menuBarManager
        if let alwaysHidden = manager.section(withName: .alwaysHidden), alwaysHidden.isEnabled, !alwaysHidden.isHidden {
            return .allRevealed
        }
        if let hidden = manager.section(withName: .hidden), !hidden.isHidden {
            return .hiddenRevealed
        }
        return .allHidden
    }
}

extension MacOS27Section {
    init(_ name: MenuBarSection.Name) {
        switch name {
        case .visible: self = .visible
        case .hidden: self = .hidden
        case .alwaysHidden: self = .alwaysHidden
        }
    }
}
