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
/// applications following that layout and the state of Ice's sections, by one of two methods
/// (see ``MacOS27HidingMethod``):
///
/// - macOS's own "Allow in the Menu Bar" switch, through `NativeAllowListConcealer27`. The
///   default since 2026-10-22, when it was measured to hide an application's items within about
///   250 ms with nothing else on the bar affected: Control Centre's modules stay, and clicks on
///   system items reach them without a lift.
/// - Assessment mode, through `MenuBarAssessmentAssertion27`. It takes Control Centre's modules
///   with it and stops clicks on system items, so Ice draws its own capture indicator and lifts
///   concealment around such clicks. Kept for systems where the switch does not work,
///   and used whenever the switch cannot be read.
@available(macOS 27.0, *)
@MainActor
final class Concealer27: ObservableObject {
    /// The two ways of hiding, as the concealer applies them.
    private enum Backend {
        case native
        case assessment
    }

    private let controller = ConcealmentController27(backend: MenuBarAssessmentAssertion27())
    private let native = NativeAllowListConcealer27()

    /// Whether the native switch can be read and written, checked once at setup.
    private var nativeIsAvailable = false

    /// Set when the native switch failed in a way that will not mend itself in this run, so
    /// concealment falls back to assessment mode rather than leave everything shown.
    private var nativeFailed = false

    /// The method in force since the last ``update()``.
    private var backend = Backend.assessment {
        didSet {
            let needsClickLift = needsClickLift
            Self.needsClickLiftSnapshot.withLock { $0 = needsClickLift }
        }
    }

    /// ``needsClickLift``, for the click tap, which runs off the main thread.
    nonisolated static let needsClickLiftSnapshot = OSAllocatedUnfairLock(initialState: true)

    /// Applications meant to be concealed that MenuBarAgent did not track at the last native
    /// apply, so there was no switch to turn off yet (see ``reapplyWhileLaunching(bundleID:)``).
    private var untrackedConcealed = Set<String>()
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
    private var temporarilyShown = [String: Int]() {
        didSet {
            isShowingTemporarily = !temporarilyShown.isEmpty
        }
    }

    /// Whether any application is shown for a moment right now — to be clicked, or photographed.
    ///
    /// An item shown this way is drawn at the left end of the run, which is where Ice's own
    /// camera and microphone indicator stands, so the indicator gets out of the way while it
    /// lasts: it was drawn over the item, and the menu that opened from it came up underneath.
    @Published private(set) var isShowingTemporarily = false

    /// Whether Ice's dividers can leave the bar.
    ///
    /// Through the native switch nothing restricts the bar, so MenuBarAgent keeps Ice's own items
    /// on it, and each divider — two points wide and drawing nothing — still gets the spacing
    /// MenuBarAgent puts between any two items: about 50 points of empty bar between visible icons
    /// on the built-in display (measured 2026-10-26). Under assessment mode MenuBarAgent dropped
    /// them on its own. Sections come from the saved layout on 27, so once that layout has been
    /// read off the bar the dividers have nothing left to mark.
    @Published private(set) var dividersMayStandAside = false
    private var cancellables = Set<AnyCancellable>()
    private var runningApplicationsObservation: NSKeyValueObservation?

    /// Whether any application is meant to be concealed right now.
    private(set) var isConcealing = false {
        didSet {
            let isConcealing = isConcealing
            Self.isConcealingSnapshot.withLock { $0 = isConcealing }
        }
    }

    /// ``isConcealing``, for the click tap, which runs off the main thread so that a busy main
    /// thread never holds up the system's clicks.
    nonisolated static let isConcealingSnapshot = OSAllocatedUnfairLock(initialState: false)

    /// Process identifiers of the applications meant to be concealed right now.
    private(set) var concealedPIDs = Set<pid_t>()

    /// Bundle identifiers of the applications meant to be concealed right now.
    private(set) var concealedBundleIDs = Set<String>()

    /// Whether Ice has read the bar once since it started.
    ///
    /// What Ice has not seen before it hides it, it cannot list afterwards: hiding takes the
    /// application out of Accessibility, so a launch that concealed before its first read left
    /// the Ice Bar with two items of eleven (seen 2026-11-04, 600 ms between Ice starting and
    /// the first concealment). The first concealment waits for that read.
    private var hasSeenBar = false

    /// The read the first concealment is waiting for.
    private var firstReadTask: Task<Void, Never>?

    /// The items each application had when it was last seen on the bar.
    ///
    /// The native switch takes a concealed application out of Accessibility altogether: it
    /// publishes no `AXExtrasMenuBar` at all while its switch is off (measured 2026-11-03), so
    /// its items are missing from every read and Ice's cache dropped them. The Ice Bar then had
    /// nothing to show and nothing to click, though the tiles for those very items were on disk
    /// (seen 2026-11-04, with `hidden=` empty in the cache while eleven applications were
    /// hidden). What Ice has hidden it still has to list, so the last account of each
    /// application's items is kept and put back while the application is concealed.
    private let rememberedItemStore = RememberedItemStore27()

    /// The section of each application. Applications missing from it are visible.
    private var savedLayout: [String: MacOS27Section] {
        let stored = Defaults.dictionary(forKey: .macOS27Layout) as? [String: Int] ?? [:]
        return stored.compactMapValues(MacOS27Section.init(rawValue:))
    }

    /// Whether a click on a system item has to lift concealment to reach it.
    ///
    /// Only under assessment mode, which has MenuBarAgent ignore those clicks. With the native
    /// switch the system items are untouched and take their clicks as they would without Ice.
    var needsClickLift: Bool {
        backend == .assessment
    }

    /// The method to apply, from the setting and what this system allows.
    private func resolvedBackend(_ appState: AppState) -> Backend {
        guard
            appState.settings.advanced.macOS27HidingMethod == .nativeAllowList,
            nativeIsAvailable,
            !nativeFailed
        else {
            return .assessment
        }
        return .native
    }

    func performSetup(with appState: AppState) {
        self.appState = appState
        nativeIsAvailable = NativeAllowListConcealer27.isAvailable
        if !nativeIsAvailable {
            logger.notice("The native Allow in the Menu Bar switch cannot be read, so assessment mode is used")
        }
        guard nativeIsAvailable || MenuBarAssessmentAssertion27.isAvailable else {
            logger.error("Neither the native switch nor MenuBarClientCore assertions are available, so items will not be hidden")
            return
        }
        NotchGeometry27.refresh()
        rememberedItemStore.load()
        let workspaceCenter = NSWorkspace.shared.notificationCenter
        for name in [NSWorkspace.didLaunchApplicationNotification, NSWorkspace.didTerminateApplicationNotification] {
            observers.append(workspaceCenter.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated {
                    self?.update()
                }
            })
        }
        // Plugging a display in lays both bars out again, and whatever does not fit beside the
        // notch is folded away — the state the check below watches for. Nothing else here notices
        // a display arriving, so without this the check waits for the next concealment change,
        // which on a quiet machine is a long way off.
        observers.append(NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                NotchGeometry27.refresh()
                self?.update()
            }
        })
        // `didLaunchApplicationNotification` arrives only once an application has finished
        // launching, and by then it has usually created its status item. The running
        // applications list changes as soon as the process checks in, which is earlier:
        // measured on macOS 27.0.1, AlDente created its item 400 ms after this fired.
        runningApplicationsObservation = NSWorkspace.shared.observe(
            \.runningApplications,
            options: [.new]
        ) { [weak self] _, change in
            guard change.kind == .insertion else {
                return
            }
            let launched = (change.newValue ?? []).compactMap { application -> (String, pid_t)? in
                guard let bundleID = application.bundleIdentifier else {
                    return nil
                }
                return (bundleID, application.processIdentifier)
            }
            Task { @MainActor in
                for (bundleID, pid) in launched {
                    self?.showWhileLaunching(bundleID: bundleID, pid: pid)
                    if self?.backend == .native {
                        self?.reapplyWhileLaunching(bundleID: bundleID)
                    }
                }
            }
        }
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
        appState.captureIndicatorPanel27.performSetup(watcher: appState.captureWatcher27, concealer: self)
        // Changing the method releases the old one in full before the new one is applied (see
        // `update`). Received on the main queue, so the setting already holds the new value.
        appState.settings.advanced.$macOS27HidingMethod
            .removeDuplicates()
            .dropFirst()
            .receive(on: DispatchQueue.main)
            .sink { [weak self] method in
                MainActor.assumeIsolated {
                    guard let self else {
                        return
                    }
                    self.logger.notice("Hiding method changed to \(method.rawValue, privacy: .public)")
                    // A lift in progress belongs to assessment mode; the new method starts clean.
                    self.suspendedUntil = nil
                    self.update()
                }
            }
            .store(in: &cancellables)
        update()
    }

    /// Derives what to conceal from Ice's sections and applies it.
    func update() {
        guard let appState else {
            return
        }
        let backend = resolvedBackend(appState)
        guard backend == .native || MenuBarAssessmentAssertion27.isAvailable else {
            return
        }
        self.backend = backend
        let mayStandAside = backend == .native && Defaults.bool(forKey: .macOS27LayoutSeeded)
        if dividersMayStandAside != mayStandAside {
            dividersMayStandAside = mayStandAside
        }
        if let suspendedUntil, ContinuousClock.now < suspendedUntil {
            return
        }
        guard hasSeenBar || barIsKnown else {
            // One read of the bar before anything is hidden, so that what is hidden can still
            // be listed afterwards (see ``hasSeenBar``). A read that comes back with nothing
            // counts too: it is the bar Ice was given, and waiting for a better one would
            // leave the items shown.
            if firstReadTask == nil {
                firstReadTask = Task { [weak self] in
                    let items = await MenuBarItemProvider27.items()
                    guard let self else {
                        return
                    }
                    remember(items: items)
                    hasSeenBar = true
                    firstReadTask = nil
                    update()
                }
            }
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
        concealedBundleIDs = concealed
        isConcealing = !target.isEmpty
        // The devices are only worth asking about while Ice's own indicator would be drawn: while
        // something is hidden, and only under assessment mode. With the native switch macOS keeps
        // drawing its own, and a second one beside it is exactly what the user saw.
        let drawsOwnIndicators = isConcealing && backend == .assessment
        appState.captureWatcher27.setWatching(drawsOwnIndicators && appState.settings.advanced.showCaptureIndicator)
        defer { MenuBarItemProvider27.setConcealedPIDs(concealedPIDs) }
        concealedPIDs = Set(applications.compactMap { application in
            guard let bundleID = application.bundleIdentifier, concealed.contains(bundleID) else {
                return nil
            }
            return application.processIdentifier
        })
        lastChangeAt = .now
        let previous = applyTask
        // Each method releases whatever the other holds before applying its own, so a change of
        // method never leaves both hiding at once, nor anything hidden by the one given up.
        let task = Task { [weak self, controller, native, logger] in
            await previous?.value
            switch backend {
            case .native:
                if controller.isActive {
                    controller.releaseAll()
                }
                do {
                    let untracked = try native.apply(concealed: concealed)
                    self?.untrackedConcealed = untracked
                } catch {
                    logger.error("Could not apply concealment through the native switch: \(error, privacy: .public)")
                    // A switch that cannot be found or read now will not be in a moment either, so
                    // assessment mode takes over for the rest of the run. A write that did not
                    // synchronize is tried again at the next change.
                    switch error as? NativeAllowListConcealer27.Failure {
                    case .unavailable, .unreadable:
                        self?.nativeFailed = true
                        self?.update()
                    default:
                        break
                    }
                }
            case .assessment:
                native.releaseAll()
                do {
                    try await controller.apply(target: target, running: running)
                } catch {
                    logger.error("Could not apply concealment: \(error, privacy: .public)")
                }
            }
        }
        applyTask = task
        // Concealing moves the remaining items, and hover hit-testing uses their cached
        // frames. The refresh stays out of `applyTask`, so a slow read never holds up the
        // next change. The bar animates for about 250 ms (measured).
        Task { [weak self] in
            await task.value
            try? await Task.sleep(for: .milliseconds(400))
            await self?.appState?.itemManager.cacheItemsIfNeeded()
            await self?.checkStuckOverflow()
        }
    }

    /// Applies the native switch again while a hidden application launches.
    ///
    /// MenuBarAgent consults the switch when an item is created, so an application that is
    /// already tracked needs nothing here: it is simply not drawn. One it has never seen has no
    /// switch until its first item exists, and is turned off once it does.
    private func reapplyWhileLaunching(bundleID: String) {
        guard let section = savedLayout[bundleID], section != .visible else {
            return
        }
        Task { [weak self] in
            for delay in [1, 3, 8] {
                try? await Task.sleep(for: .seconds(delay))
                guard let self, backend == .native, untrackedConcealed.contains(bundleID) else {
                    return
                }
                update()
            }
        }
    }

    /// How many readings in a row must disagree with what Ice is showing before it flips.
    ///
    /// A single read can catch the bar mid-animation and count wrongly, and the notice flickered
    /// on and off every few seconds because of it. See ``StuckOverflow27/DisagreementCounter``.
    private var stuckDisagreements = StuckOverflow27.DisagreementCounter(threshold: 2)

    /// Whether a notched bar looks stuck with items folded away and no way to reach them.
    ///
    /// Settings shows this, with the applications that could be the ones missing from it.
    @Published private(set) var isOverflowStuck = false

    /// The applications whose items belong on every bar while the hiding is in force.
    ///
    /// Which of them a notched bar has folded away cannot be told from the bar: the items it
    /// draws carry no owner, and Accessibility keeps reporting frames for items drawn nowhere.
    /// So they are offered to the user as the candidates to relaunch, rather than acted on.
    @Published private(set) var visibleApplications = [(bundleID: String, name: String)]()

    /// Notes whether concealment has left a notched bar's items folded with no overflow button.
    ///
    /// Seen three times here — 2026-09-29, 10-01 and 10-02 — and the third time with the trigger
    /// in hand: plugging the second display in. macOS lays both bars out again, folds what does
    /// not fit beside the notch, and never reconsiders once Ice frees the room; the "«" goes away
    /// with the items still behind it.
    ///
    /// A bar that is not the active one is read by counting: its own window lists what it draws,
    /// and the items folded away are simply absent from it while the other display draws them.
    /// That is the case that matters — the display being worked on is usually the other one, and
    /// with only the active bar's geometry to go by this watched the wrong display for two days.
    private func checkStuckOverflow() async {
        guard backend == .assessment else {
            // Folded items with no way back were an artefact of assessment mode: the native
            // switch gives the room back as MenuBarAgent lays the bar out, so there is nothing
            // to watch for, and a notice left over from the other method goes with it.
            _ = stuckDisagreements.record(disagrees: false)
            if isOverflowStuck {
                isOverflowStuck = false
            }
            return
        }
        guard isConcealing else {
            // With nothing concealed every item is on the bar, so a notched one folds what does
            // not fit and there is nothing to tell. This is also when the user is most likely to
            // be looking: opening the Menu Bar Layout window reveals everything, and the notice
            // that brought them there would otherwise disappear as they arrived.
            return
        }
        let items = await MenuBarItemProvider27.items()
        let ownPID = ProcessInfo.processInfo.processIdentifier
        let agentBundleID = MenuBarItemProvider27.menuBarAgentBundleID
        let applicationItems = items.filter { item in
            item.ownerPID != ownPID
                && !concealedPIDs.contains(item.ownerPID)
                && item.sourceApplication?.bundleIdentifier != agentBundleID
        }
        // What each bar lists, by MenuBarAgent's own account of it. Both displays list every
        // item that belongs to the bar — the one it is drawn on with a frame, the other without
        // geometry — so a bar listing fewer than another is a bar missing items. The items the
        // applications report are no use here: a folded item keeps the frame it last had, so it
        // still reads as drawn (measured 2026-10-02, with four of five items gone from the
        // built-in bar and all five still reporting frames on it).
        let counts = NSScreen.screens.reduce(into: [CGDirectDisplayID: Int]()) { counts, screen in
            counts[screen.displayID] = MenuBarItemProvider27.applicationEntryCount(for: screen.displayID)
        }
        let described = NSScreen.screens.map { screen in
            "\(screen.displayID)\(screen.hasNotch ? " notched" : "") lists \(counts[screen.displayID].map(String.init) ?? "nothing")"
        }.joined(separator: ", ")
        logger.debug("Stuck check: \(applicationItems.count, privacy: .public) items to draw; \(described, privacy: .public)")
        let chevron = MenuBarItemProvider27.overflowButtonFrame()
        let stuck = NSScreen.screens.contains { screen in
            guard screen.hasNotch, let listed = counts[screen.displayID] else {
                return false
            }
            let displayBounds = CGDisplayBounds(screen.displayID)
            // A bar with a "«" on it has folded its items away but left them a click away, which
            // is macOS behaving as it means to. Measured on 2026-10-02, the counts do not trip on
            // that anyway — a bar with the button listed 20 against the other display's 19, since
            // the button is one of its entries — but the state is worth distinguishing all the
            // same (raised by @jasonsmithio on jordanbaird/Ice#995).
            if let chevron, displayBounds.intersects(chevron) {
                return false
            }
            if let elsewhere = counts.filter({ $0.key != screen.displayID }).values.max() {
                return StuckOverflow27.isStuck(drawnApplicationItems: listed, expectedApplicationItems: elsewhere)
            }
            // The only bar there is. With nothing to compare it against, the geometry is all that
            // is left: an item under the notch, or one stacked on its neighbour, with no button to
            // reach either. It cannot see a bar that lost its items outright, but it is what the
            // check had before counting, and a MacBook on its own would otherwise go unwatched.
            return StuckOverflow27.isStuck(
                visibleItemFrames: applicationItems.filter { displayBounds.intersects($0.bounds) }.map(\.bounds),
                chevronFrame: chevron,
                notchSpan: StuckOverflow27.notchSpan(
                    displayBounds: displayBounds,
                    leftAreaWidth: screen.auxiliaryTopLeftArea?.width,
                    rightAreaWidth: screen.auxiliaryTopRightArea?.width
                )
            )
        }
        var applications = [String: String]()
        for item in applicationItems {
            guard let application = item.sourceApplication, let bundleID = application.bundleIdentifier else {
                continue
            }
            applications[bundleID] = application.localizedName ?? bundleID
        }
        let candidates = applications
            .map { (bundleID: $0.key, name: $0.value) }
            .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
        // A read that caught the bar mid-change can come back with one item or none; keeping the
        // last full answer is better than offering the user a list that empties as they look at it.
        if !candidates.isEmpty, candidates.map(\.bundleID) != visibleApplications.map(\.bundleID) {
            visibleApplications = candidates
        }
        guard stuckDisagreements.record(disagrees: stuck != isOverflowStuck) else {
            return
        }
        isOverflowStuck = stuck
        if stuck {
            logger.notice("A notched bar looks stuck: items folded away with no overflow button")
        } else {
            logger.notice("The notched bar lays its items out again")
        }
    }

    /// Quits an application and starts it again, which is what lays its items out afresh.
    ///
    /// Asked for from Settings, for the application the user can see is missing. Ice does not do
    /// it by itself: an item created while an assertion is live is laid out alone and leaves the
    /// folded ones where they are (measured 2026-10-02, restarting TextInputMenuAgent brought
    /// back its own item and nothing else), so only the owner can bring an item back — and the
    /// owner is the user's application, not Ice's to close unasked.
    func relaunch(bundleID: String) {
        guard
            let application = NSRunningApplication.runningApplications(withBundleIdentifier: bundleID).first,
            let url = application.bundleURL
        else {
            logger.warning("Cannot relaunch \(bundleID, privacy: .public): it is not running")
            return
        }
        logger.notice("Relaunching \(bundleID, privacy: .public) to lay its menu bar items out again")
        application.terminate()
        Task { [logger] in
            for _ in 0..<40 where !application.isTerminated {
                try? await Task.sleep(for: .milliseconds(250))
            }
            // An agent launchd keeps alive is back on its own by now, and opening it again does
            // nothing; an application that refused to quit is left exactly as it was.
            guard application.isTerminated else {
                logger.warning("\(bundleID, privacy: .public) did not quit, so it was left alone")
                return
            }
            let configuration = NSWorkspace.OpenConfiguration()
            configuration.activates = false
            do {
                try await NSWorkspace.shared.openApplication(at: url, configuration: configuration)
            } catch {
                logger.error("Could not start \(bundleID, privacy: .public) again: \(error, privacy: .public)")
            }
        }
    }

    /// Releases every assertion for a moment, so a click can reach a system item.
    ///
    /// Does nothing with the native switch, where clicks reach system items anyway.
    func suspend(for duration: Duration) {
        guard needsClickLift else {
            return
        }
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

    /// Ends a suspension before its time, so the items are hidden again as soon as whatever
    /// needed them shown is done. The flash of revealed items is all the user sees of a lift, so
    /// the less of it there is, the better.
    func resumeConcealing() {
        guard suspendedUntil != nil else {
            return
        }
        suspendedUntil = nil
        update()
    }

    /// Releases every assertion and returns once that has actually happened.
    ///
    /// Releasing goes through MenuBarAgent and queues behind whatever concealment change came
    /// before it. A click replayed on a timer could therefore arrive while the assertion was
    /// still live, and MenuBarAgent ignores those — which is why a click on the clock sometimes
    /// did nothing and worked on the second try.
    func suspendReleased(for duration: Duration) async {
        guard needsClickLift else {
            return
        }
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

    /// The shortest wait before a shown item counts as drawn.
    ///
    /// Assessment mode leaves a concealed item in Accessibility's account of the bar, at the
    /// frame it last had, so the moment the application is shown it reads as drawn whether it
    /// has been laid out or not. The floor is what keeps a caller from acting on that stale
    /// frame: an item is drawn 0.4–0.6 s after its application is allowed (measured).
    private static let drawFloor = Duration.milliseconds(500)

    /// The longest ``showTemporarily(bundleID:untilDrawn:)`` waits beyond that.
    ///
    /// Not every item comes back drawn. Docker Desktop's and Pritunl's are put back on the bar
    /// where MenuBarAgent last had them, which on the built-in display is beside the notch where
    /// nothing is drawn, and they stay undrawn however long Ice waits (measured 2026-11-04:
    /// 4.8 s and 5.1 s, both the whole wait). Waiting past this only delays the caller's own
    /// answer to that — expanding the system overflow and clicking what it unfolds, a press
    /// through Accessibility, or no tile for a photograph.
    private static let drawTimeout = Duration.milliseconds(1500)

    /// When an item missing from Accessibility altogether counts as folded into the system
    /// overflow rather than merely slow to arrive.
    ///
    /// An item folded into the overflow is published by nobody: its application answers no
    /// item of its own for as long as it stays folded (measured 2026-11-04 on Docker Desktop,
    /// `kAXErrorNoValue` through a 4.5 s wait). So absence, once an item would have arrived,
    /// says where it is — and the caller can act on that instead of waiting out ``drawTimeout``.
    /// The floor is what tells absence from not yet: an item that does fit was published 0.52
    /// to 0.61 s after its application was allowed (measured 2026-11-04 over five clicks).
    private static let foldedVerdict = Duration.milliseconds(900)

    /// Below this an item is a sliver, not something the user can see or click. An item that
    /// sizes itself to the room it is offered can settle there and never grow back
    /// (jordanbaird/Ice#1007), and a sliver is no good to a caller about to click it.
    private static let minimumDrawnWidth: CGFloat = 4

    /// Shows an application and waits for its item to be drawn, for a caller about to click or
    /// photograph it. Answers the item, or `nil` if it never appeared. Balanced by
    /// ``endTemporaryShow(bundleID:)`` like the plain show.
    ///
    /// Ice waited a fixed 600 ms before, which is what an item takes to be drawn once assessment
    /// mode stops hiding it. The native switch takes the item off the bar altogether: while an
    /// application is concealed Accessibility reports no `AXExtrasMenuBar` for it at all
    /// (measured 2026-11-03: ten of twelve concealed applications answered `kAXErrorNoValue`),
    /// and the item is published again only once MenuBarAgent has laid the bar out afresh. That
    /// took longer than the fixed wait, so a click on a hidden item ended in "neither drawn nor
    /// reachable through Accessibility" and Ice concealed the application again while the user
    /// watched its item appear and go.
    ///
    /// - Parameter windowID: The item to wait for. Any item of the application when `nil`.
    func showTemporarily(bundleID: String, untilDrawn windowID: CGWindowID?) async -> MenuBarItem? {
        showTemporarily(bundleID: bundleID)
        return await drawnItem(bundleID: bundleID, windowID: windowID, floor: Self.drawFloor, timeout: Self.drawTimeout)
    }

    /// Waits for a shown application's item to be drawn, without showing it: the caller has
    /// done that already.
    ///
    /// Called a second time after the system overflow is expanded, where neither wait applies
    /// as it does to a freshly shown application — the item is published the moment it is
    /// unfolded, so there is no floor, and it either arrives at once or not at all.
    /// - Parameter acrossNotchIsFinal: Whether an item laid out across the notch means the wait
    ///   is over. It does for a freshly shown application, which is put back where MenuBarAgent
    ///   last had it and stays there. It does not after the overflow is expanded, where that is
    ///   just where the item was while it was folded: it is laid out afresh a moment later
    ///   (measured 2026-11-04: 0.17 s, from x=-834 across the notch to x=-1084 beside it).
    func drawnItem(
        bundleID: String,
        windowID: CGWindowID?,
        floor: Duration,
        timeout: Duration,
        acrossNotchIsFinal: Bool = true
    ) async -> MenuBarItem? {
        let started = ContinuousClock.now
        func isWanted(_ item: MenuBarItem) -> Bool {
            if let windowID {
                return item.windowID == windowID
            }
            return item.sourceApplication?.bundleIdentifier == bundleID
        }
        while true {
            let items = await MenuBarItemProvider27.items()
            let wanted = items.filter(isWanted)
            // Kept side by side with the frames handed to the verdict, so the item the
            // verdict names comes back by index rather than by looking a frame up again.
            let drawn = wanted.filter(\.isOnScreen)
            let undrawn = wanted.filter { !$0.isOnScreen }
            let activeDisplayID = Bridging.getActiveMenuBarDisplayID()
            let indicator = MenuBarItemProvider27.overflowIndicator(for: activeDisplayID, expanded: false)
            let elapsed = ContinuousClock.now - started
            let verdict = DrawWait27.verdict(DrawWait27.Input(
                elapsed: elapsed,
                floor: floor,
                timeout: timeout,
                foldedVerdict: Self.foldedVerdict,
                drawnFrames: drawn.map(\.bounds),
                undrawnFrames: undrawn.map(\.bounds),
                minimumWidth: Self.minimumDrawnWidth,
                notchXRange: NotchGeometry27.notchXRange(for: activeDisplayID),
                activeDisplayBounds: activeDisplayID.map(CGDisplayBounds),
                hasCollapsedOverflow: indicator != nil,
                acrossNotchIsFinal: acrossNotchIsFinal
            ))
            switch verdict {
            case .keepWaiting:
                try? await Task.sleep(for: .milliseconds(120))
            case .drawn(let index):
                logger.notice("\(bundleID, privacy: .public) drawn \(elapsed, privacy: .public) after it was shown")
                return drawn[index]
            case .folded:
                logger.notice(
                    """
                    \(bundleID, privacy: .public) is folded into the system overflow at \
                    x=\(indicator?.frame.minX ?? 0, privacy: .public): Accessibility has no item of it \
                    \(elapsed, privacy: .public) after it was shown
                    """
                )
                return nil
            case .acrossNotch(let frame):
                logger.notice(
                    """
                    \(bundleID, privacy: .public) was laid out across the notch \
                    at x=\(frame.minX, privacy: .public): there is no room for it beside the notch
                    """
                )
                return nil
            case .timedOut:
                let seen = wanted.map { String(format: "[x=%.0f w=%.0f]", $0.bounds.minX, $0.bounds.width) }
                logger.notice(
                    """
                    \(bundleID, privacy: .public) was not drawn within \(timeout, privacy: .public); \
                    Accessibility reports \(seen.isEmpty ? "no item of it" : seen.joined(separator: " "), privacy: .public), \
                    system overflow button at \(MenuBarItemProvider27.overflowButtonFrame().map { String(format: "x=%.0f w=%.0f", $0.minX, $0.width) } ?? "none", privacy: .public)
                    """
                )
                return nil
            }
        }
    }

    /// The longest Ice watches a launching application for its item.
    ///
    /// This bounds the watching, not the showing. It used to bound both, at 8 seconds, and
    /// concealing the application when it ran out was the bug: Slack, Docker Desktop, Pritunl
    /// and Claude all reached the deadline with no item at all (measured 2026-11-10, each
    /// logged `item width 0.000000`), and an item created while its application is concealed
    /// is never drawn again. Not after the application is relaunched — only after MenuBarAgent
    /// is. So an application whose item never arrived is now left on the bar.
    ///
    /// 45 seconds is a judgement, not a measurement: nobody has timed how long the slowest
    /// application takes to publish its item. Being too generous costs a poll of the bar three
    /// times a second for a while longer; being too mean used to cost the item itself.
    private static let launchGrace = Duration.seconds(45)

    /// Applications shown while they create their status items, with when each gives up.
    private var launching = [String: (pid: pid_t, deadline: ContinuousClock.Instant)]()

    /// The one task that watches for their items, however many are launching at once.
    private var launchWatcher: Task<Void, Never>?

    /// Shows a concealed application while it creates its status item.
    ///
    /// An item created while its application is concealed is offered no room, and an item
    /// that sizes itself to that room — AlDente's, for one — settles at about 3 pt and never
    /// grows back, not even after Ice quits; only relaunching the application without Ice fixes
    /// it. Items of a fixed length, Amphetamine's for one, are not affected (measured on
    /// macOS 27.0.1, 2026-10-01). Reported as jordanbaird/Ice#1007.
    ///
    /// The native switch spares the item that fate — MenuBarAgent consults the switch as the
    /// item is created, so an application launched while hidden is simply not drawn (measured on
    /// macOS 27.0.1, 2026-10-22) — but leaves a worse one in its place: an item created while
    /// its switch is off is never published through Accessibility afterwards, not even once the
    /// switch goes back on. Ice then has nothing to click and nothing to photograph for the Ice
    /// Bar, and the item is only reachable by relaunching the application. Measured 2026-11-04
    /// on Docker Desktop: its process answered `kAXErrorNoValue` through two whole reveals while
    /// its item was plainly on the bar. So both methods show an application while it creates
    /// its item.
    private func showWhileLaunching(bundleID: String, pid: pid_t) {
        guard
            let section = savedLayout[bundleID],
            section != .visible,
            launching[bundleID] == nil
        else {
            return
        }
        logger.notice("Showing launching \(bundleID, privacy: .public) until its item exists")
        launching[bundleID] = (pid, .now + Self.launchGrace)
        showTemporarily(bundleID: bundleID)
        startLaunchWatcher()
    }

    /// Watches for the items of every application being shown while it launches.
    ///
    /// One watcher for all of them, rather than one each: a login starts the hidden applications
    /// together, and a read of every process's items for each of them, three times a second, is a
    /// load worth not creating (raised by @jasonsmithio on jordanbaird/Ice#995).
    private func startLaunchWatcher() {
        guard launchWatcher == nil else {
            return
        }
        launchWatcher = Task { [weak self] in
            while true {
                try? await Task.sleep(for: .milliseconds(300))
                guard let self, !launching.isEmpty else {
                    break
                }
                let items = await MenuBarItemProvider27.items()
                let now = ContinuousClock.now
                for (bundleID, entry) in launching {
                    // The process is looked up afresh on every tick rather than kept from the
                    // moment the window opened: changing the item spacing quits and relaunches
                    // every application that has an item, so the application comes back under
                    // another pid and its new item belongs to that one. Matching on the pid the
                    // window opened on meant a relaunched application's item was never
                    // recognised and the window always ran to its full deadline, leaving the
                    // application shown for eight seconds instead of until its item existed
                    // (measured 2026-11-04 on Docker Desktop).
                    //
                    // An application that is not listed at all keeps the pid it started with and
                    // keeps its window open until the deadline. Reading "not listed" as "gone"
                    // and concealing it there broke the bar once already: that gap is the moment
                    // between the old process dying and the new one appearing, which is the
                    // middle of a relaunch — exactly when the item being created must not be
                    // concealed, because an item created while its application is concealed is
                    // never published afterwards.
                    let pid = NSRunningApplication
                        .runningApplications(withBundleIdentifier: bundleID)
                        .first?
                        .processIdentifier ?? entry.pid
                    if let item = items.first(where: { $0.ownerPID == pid && $0.bounds.width > 4 }) {
                        endLaunchGrace(bundleID: bundleID, width: item.bounds.width)
                    } else if now > entry.deadline {
                        abandonLaunchGrace(bundleID: bundleID)
                    }
                }
            }
            self?.launchWatcher = nil
        }
    }

    /// Stops watching an application whose item never arrived, and leaves it on the bar.
    ///
    /// Concealing it here is what the deadline used to do, and it is the one moment at which
    /// concealing does lasting damage: the item being created goes to an application macOS has
    /// been told to keep off the bar, and macOS then never draws it, however the application is
    /// restarted afterwards. A visible item the user wanted hidden is a small annoyance they
    /// can fix; an item nothing will draw is not.
    private func abandonLaunchGrace(bundleID: String) {
        guard launching.removeValue(forKey: bundleID) != nil else {
            return
        }
        logger.notice(
            """
            \(bundleID, privacy: .public) published no item within \(Self.launchGrace, privacy: .public); \
            leaving it on the bar, because concealing an application while it creates its item \
            is what stops macOS drawing that item at all
            """
        )
    }

    /// Conceals an application again once its item exists.
    private func endLaunchGrace(bundleID: String, width: CGFloat) {
        guard launching.removeValue(forKey: bundleID) != nil else {
            return
        }
        logger.notice("Concealing \(bundleID, privacy: .public) again, item width \(width, privacy: .public)")
        Task { [weak self] in
            // Let the item finish laying out before it is concealed again.
            try? await Task.sleep(for: Self.settleAfterChange)
            self?.endTemporaryShow(bundleID: bundleID)
        }
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

    /// Writes the sections the bar still holds from before macOS 27 into the saved layout, once.
    ///
    /// Nothing recorded them before: an item's section was where it sat between Ice's dividers.
    /// On 27 that order no longer means anything, and an application missing from the layout is
    /// visible, so without this an upgrade left Ice hiding nothing until the whole layout was
    /// rebuilt by hand — reported on jordanbaird/Ice#1006, and the likeliest reading of several
    /// "Ice hides nothing on 27" issues.
    ///
    /// The bar is read once, the first time it can be: a user who has arranged a layout of their
    /// own keeps it, and a bar whose order macOS 27 has already rearranged is left alone (see
    /// ``SectionLayout27/seededLayout(items:hiddenControlItem:alwaysHiddenControlItem:)``).
    func seedLayoutIfNeeded(items: [MenuBarItem]) {
        guard
            !Defaults.bool(forKey: .macOS27LayoutSeeded),
            savedLayout.isEmpty,
            !isConcealing,
            let hiddenControlItem = items.first(where: { $0.tag == .hiddenControlItem })
        else {
            return
        }
        // Once the bar can be read, this runs whatever it says: a bar that says nothing is still
        // an answer, and asking it again later would risk reading one Ice itself had concealed.
        Defaults.set(true, forKey: .macOS27LayoutSeeded)
        let alwaysHiddenControlItem = items.first { $0.tag == .alwaysHiddenControlItem }
        let managed = items.compactMap { item -> (bundleID: String, bounds: CGRect)? in
            guard
                item.canBeHidden,
                !item.isSystemClone,
                !item.isControlItem,
                let bundleID = item.sourceApplication?.bundleIdentifier
            else {
                return nil
            }
            return (bundleID, item.bounds)
        }
        guard let seeded = SectionLayout27.seededLayout(
            items: managed,
            hiddenControlItem: hiddenControlItem.bounds,
            alwaysHiddenControlItem: alwaysHiddenControlItem?.bounds
        ) else {
            logger.notice("The bar's order says nothing about sections, so the macOS 27 layout stays empty")
            // Seeded all the same, so the dividers are free to leave the bar.
            update()
            return
        }
        Defaults.set(seeded.mapValues(\.rawValue), forKey: .macOS27Layout)
        let described = seeded
            .sorted { $0.key < $1.key }
            .map { "\($0.key)=\($0.value.rawValue)" }
            .joined(separator: " ")
        logger.notice("Took the macOS 27 layout from the order on the bar: \(described, privacy: .public)")
        update()
    }

    /// Builds the item cache from the saved layout rather than the order on the bar.
    func cacheFromSavedLayout(items: [MenuBarItem], displayID: CGDirectDisplayID?) -> MenuBarItemManager.ItemCache {
        remember(items: items)
        var cache = MenuBarItemManager.ItemCache(displayID: displayID)
        let layout = savedLayout
        let all = items + concealedItemsMissing(from: items)
        for item in all.sorted(by: { $0.bounds.minX < $1.bounds.minX }) where !item.isSystemClone {
            // An item macOS 27 draws itself — the clock, Wi-Fi, the battery, Control Centre —
            // can be neither hidden nor moved by Ice, but leaving it out made the layout
            // window an incomplete account of the bar. It is listed under "Visible", where it
            // always is, and `MenuBarItemTag.isMovable` is what dims it and refuses the drag.
            guard item.canBeHidden else {
                cache[.visible].append(item)
                continue
            }
            if item.isControlItem {
                if item.tag == .visibleControlItem {
                    cache[.visible].append(item)
                }
                continue
            }
            switch layout[item.sourceApplication?.bundleIdentifier ?? ""] ?? .visible {
            case .visible: cache[.visible].append(item)
            case .hidden: cache[.hidden].append(item)
            case .alwaysHidden: cache[.alwaysHidden].append(item)
            }
        }
        return cache
    }

    /// Keeps the latest account of the items of every application that reported any.
    ///
    /// An application that reports nothing keeps the account it had: that is the concealed one
    /// whose items are to be remembered. One whose process is gone is forgotten, so a restarted
    /// application is never remembered by the identifiers of the process it replaced.
    private func remember(items: [MenuBarItem]) {
        rememberedItemStore.remember(items)
    }

    /// Whether what every concealed application in the saved layout has on the bar is already
    /// known, from this run or from the last one.
    ///
    /// A concealed application publishes nothing through Accessibility, so Ice can only list its
    /// items from what it remembers. Reading the bar once before the first concealment is a race
    /// Ice loses when the read lands before the items are published, and it leaves every item
    /// shown while the read runs (measured 2026-11-04: 4 s at launch, and one launch in several
    /// came up with an empty Ice Bar all the same). What was remembered last time settles both.
    private var barIsKnown: Bool {
        let running = Set(NSWorkspace.shared.runningApplications.compactMap(\.bundleIdentifier))
        return rememberedItemStore.knowsEveryItem(
            of: savedLayout.filter { $0.value != .visible && running.contains($0.key) }.keys
        )
    }

    /// The remembered items of the concealed applications that this read has no account of.
    private func concealedItemsMissing(from items: [MenuBarItem]) -> [MenuBarItem] {
        rememberedItemStore.items(ofConcealed: concealedBundleIDs, missingFrom: items)
    }

    // MARK: Private

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
