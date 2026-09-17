//
//  MenuBarManager.swift
//  Ice
//

import Combine
import OSLog
import SwiftUI

/// Manager for the state of the menu bar.
@MainActor
final class MenuBarManager: ObservableObject {
    /// Information for the menu bar's average color.
    @Published private(set) var averageColorInfo: MenuBarAverageColorInfo?

    /// A Boolean value that indicates whether the menu bar is either always hidden
    /// by the system, or automatically hidden and shown by the system based on the
    /// location of the mouse.
    @Published private(set) var isMenuBarHiddenBySystem = false

    /// A Boolean value that indicates whether the menu bar is hidden by the system
    /// according to a value stored in UserDefaults.
    @Published private(set) var isMenuBarHiddenBySystemUserDefaults = false

    /// A Boolean value that indicates whether the "ShowOnHover" feature is allowed.
    @Published var showOnHoverAllowed = true

    /// Reference to the settings window.
    @Published private var settingsWindow: NSWindow?

    /// Logger for the menu bar manager.
    private let logger = Logger(category: "MenuBarManager")

    /// The shared app state.
    private weak var appState: AppState?

    /// Storage for internal observers.
    private var cancellables = Set<AnyCancellable>()

    /// A Boolean value that indicates whether the application menus are hidden.
    private var isHidingApplicationMenus = false

    /// The panel that contains the Ice Bar interface.
    let iceBarPanel = IceBarPanel()

    /// The panel that contains the menu bar search interface.
    let searchPanel = MenuBarSearchPanel()

    /// The panel that contains a portable version of the menu bar
    /// appearance editor interface
    let appearanceEditorPanel = MenuBarAppearanceEditorPanel()

    /// macOS 27's assignment-backed menu bar compatibility controller.
    let macOS27Controller = MacOS27MenuBarController()
    private let nativeHiding = MacOS27NativeMenuBarHiding()
    private var nativeConcealmentTask: Task<Void, Never>?
    private var nativeConcealmentCheckTask: Task<Void, Never>?

    /// The off-main-thread menu bar color sample.
    private var averageColorTask: Task<Void, Never>?

    /// The one-per-launch pass that photographs concealed items.
    private var glyphPhotoPassTask: Task<Void, Never>?
    private var hasRunGlyphPhotoPass = false
    private var lastNativeVisibilityDecision: String?
    /// The time of the last change to which items the spacers conceal.
    private var lastNativeConcealmentChange: ContinuousClock.Instant?
    private var deferredNativeVisibilityTask: Task<Void, Never>?
    /// The minimum time between concealment changes, long enough for
    /// MenuBarAgent's overflow animation to finish.
    private static let nativeConcealmentChangeInterval = Duration.milliseconds(400)
    private var nativeVisibilityGeneration: UInt64 = 0
    private var nativeDragVisibility = MacOS27NativeDragVisibilityState()
    /// The time of the user's most recent explicit section toggle. Ice only
    /// sends a native drag to align its boundary shortly after one.
    private var lastUserToggleTimestamp: ContinuousClock.Instant?
    /// Whether an automatic hide couldn't align Ice's boundary without a drag.
    private var needsUserActionToAlignBoundary = false
    /// The number of active temporary reveals of items concealed for the Ice Bar.
    private var iceBarRevealDepth = 0

    /// The managed sections in the menu bar.
    let sections = [
        MenuBarSection(name: .visible),
        MenuBarSection(name: .hidden),
        MenuBarSection(name: .alwaysHidden),
    ]

    /// A Boolean value that indicates whether at least one of the manager's
    /// sections is visible.
    var hasVisibleSection: Bool {
        sections.contains { !$0.isHidden }
    }

    /// Performs the initial setup of the menu bar manager.
    func performSetup(with appState: AppState) {
        self.appState = appState
        macOS27Controller.onEditingChanged = { [weak self] in
            self?.syncNativeVisibility()
        }
        configureCancellables()
        iceBarPanel.performSetup(with: appState)
        searchPanel.performSetup(with: appState)
        appearanceEditorPanel.performSetup(with: appState)
        for section in sections {
            section.performSetup(with: appState)
        }
        if #available(macOS 27.0, *) {
            nativeHiding.prepare(section: .hidden, anchorPosition: controlItem(withName: .visible)?.preferredPosition ?? 0)
        }
    }

    /// Applies only Ice-owned spacer state. Other status items receive native input.
    func syncNativeVisibility() {
        guard #available(macOS 27.0, *), let appState else { return }
        guard nativeDragVisibility.shouldApplyVisibilityUpdate() else {
            logNativeVisibilityDecision("deferred until a native drag ends")
            return
        }
        guard let screen = controlItem(withName: .visible)?.screen ?? NSScreen.main else {
            logNativeVisibilityDecision("no screen for Ice's button")
            return
        }
        let cache = appState.itemManager.itemCache
        let controlPosition = controlItem(withName: .visible)?.preferredPosition ?? 0
        // Physical position, not the previous cache's membership, determines
        // what gets hidden. The first item can have just been dragged left.
        // With the Ice Bar, hidden items stay concealed in the menu bar while
        // the bar displays them, except while one is being clicked.
        let usesIceBar = appState.settings.general.useIceBar
        let hideHidden = usesIceBar
            ? iceBarRevealDepth == 0
            : section(withName: .hidden)?.isHidden == true
        let hideAlwaysHidden = !usesIceBar && !hideHidden && !cache[.alwaysHidden].isEmpty &&
            section(withName: .alwaysHidden)?.isEnabled == true &&
            section(withName: .alwaysHidden)?.isHidden == true
        let iceBounds = macOS27Controller.knownItemsForReordering()
            .first(matching: .visibleControlItem)?.bounds
        let alwaysAnchor = if let leftmostHidden = cache[.hidden].first, let iceBounds {
            controlPosition + max(0, iceBounds.minX - leftmostHidden.bounds.minX)
        } else {
            controlPosition
        }

        if macOS27Controller.isLayoutEditing {
            logNativeVisibilityDecision("showing all items while Layout is editing (reordering: \(macOS27Controller.isReorderInProgress))")
            cancelNativeConcealment()
            if macOS27Controller.isReorderInProgress {
                nativeHiding.showForLayout(
                    anchorPosition: controlPosition,
                    alwaysHiddenAnchor: section(withName: .alwaysHidden)?.isEnabled == true ? alwaysAnchor : nil
                )
            } else {
                nativeHiding.setHidden(false, section: .hidden, anchorPosition: controlPosition, screen: screen)
                nativeHiding.setHidden(false, section: .alwaysHidden, anchorPosition: alwaysAnchor, screen: screen)
            }
            macOS27Controller.isConcealingItems = false
            return
        }

        // Coalesce rapid toggles. MenuBarAgent animates every overflow change,
        // and starting another one mid-animation leaves items flashing. The
        // control item's state still updates immediately; the latest requested
        // state is applied once the previous change has finished animating.
        let changesConcealment = hideHidden != nativeHiding.isConcealing(.hidden) ||
            hideAlwaysHidden != nativeHiding.isConcealing(.alwaysHidden)
        if changesConcealment, let lastChange = lastNativeConcealmentChange {
            let elapsed = lastChange.duration(to: .now)
            if elapsed < Self.nativeConcealmentChangeInterval {
                logNativeVisibilityDecision("waiting for the previous change to finish animating")
                scheduleDeferredNativeVisibilitySync(after: Self.nativeConcealmentChangeInterval - elapsed)
                return
            }
        }

        if hideHidden, !nativeHiding.isConcealing(.hidden) {
            guard nativeConcealmentTask == nil else {
                logNativeVisibilityDecision("hide already in progress")
                return
            }
            let generation = nativeVisibilityGeneration
            let isUserInitiated = lastUserToggleTimestamp.map { $0.duration(to: .now) < .seconds(3) } ?? false
            // After an automatic attempt couldn't align the boundary without a
            // drag, wait for the user instead of republishing the handle on
            // every cache refresh.
            guard isUserInitiated || !needsUserActionToAlignBoundary else {
                logNativeVisibilityDecision("waiting for a user action to align Ice's boundary")
                return
            }
            nativeHiding.prepareForHiding(anchorPosition: controlPosition)
            logNativeVisibilityDecision("hiding: checking Ice's boundary (user initiated: \(isUserInitiated))")
            nativeConcealmentTask = Task { [weak self] in
                guard let self else { return }
                // No mouse monitor: only an explicit request to hide reaches
                // this check. Moving our blank boundary leaves every other
                // app's native input and the user's new order untouched.
                let aligned = await appState.itemManager.alignNativeHidingBoundary(
                    updatingCache: true,
                    displayID: screen.displayID,
                    allowingDrag: isUserInitiated
                )
                guard !Task.isCancelled, generation == nativeVisibilityGeneration else {
                    logNativeVisibilityDecision("hide cancelled by a newer request")
                    return
                }
                nativeConcealmentTask = nil
                guard aligned else {
                    logger.error("Keeping items expanded because Ice's boundary could not be verified")
                    needsUserActionToAlignBoundary = !isUserInitiated
                    // The failed attempt published a narrow drag handle. A
                    // logical state reset alone leaves that empty native slot
                    // behind; withdraw both handles before reporting expanded.
                    nativeHiding.setHidden(false, section: .hidden, anchorPosition: controlPosition, screen: screen)
                    nativeHiding.setHidden(false, section: .alwaysHidden, anchorPosition: alwaysAnchor, screen: screen)
                    macOS27Controller.isConcealingItems = false
                    for section in sections { section.controlItem.state = .showSection }
                    return
                }
                needsUserActionToAlignBoundary = false
                if usesIceBar {
                    // Concealed items aren't drawn, so the Ice Bar can only show
                    // images captured while they're still in the menu bar.
                    await appState.imageCache.captureMacOS27Images(for: .hidden, onlyIfMissing: true)
                    guard !Task.isCancelled, generation == nativeVisibilityGeneration else { return }
                }
                nativeHiding.setHidden(false, section: .alwaysHidden, anchorPosition: alwaysAnchor, screen: screen)
                nativeHiding.setHidden(
                    true,
                    section: .hidden,
                    anchorPosition: controlPosition,
                    screen: screen,
                    controlFrame: currentIceButtonFrame()
                )
                lastNativeConcealmentChange = .now
                macOS27Controller.isConcealingItems = true
                logNativeVisibilityDecision("hidden: \(nativeHiding.debugDescription(for: .hidden))")
                scheduleNativeConcealmentCheck(screen: screen)
                scheduleGlyphPhotoPass(screen: screen)
            }
            return
        }

        if !hideHidden { cancelNativeConcealment() }
        let wasConcealing = nativeHiding.isConcealing(.hidden) || nativeHiding.isConcealing(.alwaysHidden)
        nativeHiding.setHidden(hideAlwaysHidden, section: .alwaysHidden, anchorPosition: alwaysAnchor, screen: screen)
        // Keep an already-concealing spacer at its current length. Resizing it
        // after Ice's button moves makes the whole bar reflow again.
        nativeHiding.setHidden(hideHidden, section: .hidden, anchorPosition: controlPosition, screen: screen)
        if changesConcealment {
            lastNativeConcealmentChange = .now
        }
        macOS27Controller.isConcealingItems = hideHidden || hideAlwaysHidden
        logNativeVisibilityDecision(
            "applied: hidden=\(hideHidden), alwaysHidden=\(hideAlwaysHidden), " +
            "\(nativeHiding.debugDescription(for: .hidden)), always \(nativeHiding.debugDescription(for: .alwaysHidden))"
        )
        if macOS27Controller.isConcealingItems, !wasConcealing {
            scheduleNativeConcealmentCheck(screen: screen)
        }
    }

    /// Photographs concealed items that have no picture yet.
    ///
    /// A crowded menu bar leaves macOS no room to draw the hidden items even
    /// when Ice reveals them, so they can never be photographed all at once.
    /// The spacer is given back a little at a time instead: macOS draws the
    /// next few items, they're photographed and saved to disk, and the spacer
    /// is restored. It runs once per launch, and only for items whose picture
    /// is missing.
    @available(macOS 27.0, *)
    private func scheduleGlyphPhotoPass(screen: NSScreen) {
        guard !hasRunGlyphPhotoPass, appState?.settings.general.useIceBar == true else {
            return
        }
        hasRunGlyphPhotoPass = true
        glyphPhotoPassTask?.cancel()
        glyphPhotoPassTask = Task { [weak self] in
            do { try await Task.sleep(for: .seconds(3)) } catch { return }
            await self?.runGlyphPhotoPass(screen: screen)
        }
    }

    @available(macOS 27.0, *)
    private func runGlyphPhotoPass(screen: NSScreen) async {
        guard
            let appState,
            ScreenCapture.cachedCheckPermissions(),
            !appState.navigationState.isIceBarPresented,
            !appState.navigationState.isSettingsPresented,
            nativeHiding.isConcealing(.hidden),
            let fullLength = nativeHiding.spacerLength(for: .hidden)
        else {
            return
        }
        let controlPosition = controlItem(withName: .visible)?.preferredPosition ?? 0

        func itemsNeedingPictures() -> [MenuBarItem] {
            let items = appState.itemManager.itemCache.managedItems
            return appState.itemManager.itemCache.managedItems(for: .hidden).filter { item in
                guard MacOS27SavedItemImages.allowsPhoto(item) else { return false }
                guard appState.imageCache.images[item.tag] == nil else { return false }
                let key = MacOS27SavedItemImages.key(for: item, among: items)
                return MacOS27SavedItemImages.image(forKey: key) == nil
            }
        }

        guard !itemsNeedingPictures().isEmpty else {
            return
        }
        logger.notice("Photographing \(itemsNeedingPictures().count, privacy: .public) concealed items")

        var length = fullLength
        let step: CGFloat = 60
        var stepsWithoutProgress = 0
        var remainingBefore = itemsNeedingPictures().count
        while length > 1, !Task.isCancelled {
            // The last step gives back the spacer's own width too: macOS keeps
            // the whole group in its overflow unless every item fits.
            length = max(1, length - step)
            nativeHiding.setConcealingLength(length, section: .hidden, anchorPosition: controlPosition)
            do { try await Task.sleep(for: .milliseconds(650)) } catch { break }
            if MacOS27GlyphDebug.isEnabled, length <= 180 {
                MacOS27MenuBarItemProvider.dumpMenuBarAgentTree()
            }
            if MacOS27GlyphDebug.isEnabled {
                let own = MacOS27MenuBarItemProvider.ownMenuBarItems()
                    .map { "\($0.tag.title)=\($0.bounds.debugDescription)" }
                    .joined(separator: " ")
                MacOS27GlyphDebug.log("Pass step: spacer=\(length) own: \(own) overflow: \(MacOS27MenuBarItemProvider.overflowControlFrames)")
            }
            await appState.imageCache.captureMacOS27Images(for: .hidden, onlyIfMissing: true)
            let remaining = itemsNeedingPictures().count
            if remaining == 0 || appState.navigationState.isIceBarPresented {
                break
            }
            // A full menu bar leaves macOS no room no matter how much space
            // the spacer gives back. Stop shuffling the bar for nothing.
            stepsWithoutProgress = remaining < remainingBefore ? 0 : stepsWithoutProgress + 1
            remainingBefore = remaining
            if stepsWithoutProgress >= 3, length <= 120 {
                logger.notice("Stopping the photo pass: macOS is not drawing the concealed items")
                break
            }
        }

        let remaining = itemsNeedingPictures().count
        logger.notice("Photo pass finished with \(remaining, privacy: .public) items still missing a picture")
        nativeHiding.setHidden(
            true,
            section: .hidden,
            anchorPosition: controlPosition,
            screen: screen,
            controlFrame: currentIceButtonFrame()
        )
        lastNativeConcealmentChange = .now
    }

    /// Confirms that Ice's own button is still on the bar after a spacer was
    /// widened. The always-hidden spacer's position is a guess, and a spacer
    /// that lands to the right of Ice pushes Ice's button into the overflow,
    /// leaving no way to click it. Withdraw the spacers if that happens.
    @available(macOS 27.0, *)
    private func scheduleNativeConcealmentCheck(screen: NSScreen) {
        nativeConcealmentCheckTask?.cancel()
        nativeConcealmentCheckTask = Task { [weak self] in
            // Accessibility can briefly report no settled frame while hosted
            // variants update, so only a repeated miss counts as a failure.
            for _ in 0 ..< 4 {
                do { try await Task.sleep(for: .milliseconds(250)) } catch { return }
                guard let self, macOS27Controller.isConcealingItems else { return }
                if isIceButtonOnBar(screen: screen) { return }
            }
            guard let self, !Task.isCancelled, macOS27Controller.isConcealingItems else { return }
            logger.error("Ice's button left the menu bar after hiding; showing all items")
            let controlPosition = controlItem(withName: .visible)?.preferredPosition ?? 0
            cancelNativeConcealment()
            nativeHiding.setHidden(false, section: .alwaysHidden, anchorPosition: controlPosition, screen: screen)
            nativeHiding.setHidden(false, section: .hidden, anchorPosition: controlPosition, screen: screen)
            macOS27Controller.isConcealingItems = false
            for section in sections { section.controlItem.state = .showSection }
        }
    }

    /// Returns whether Ice's visible control item is on the menu bar strip of
    /// the given screen and to the right of every widened spacer.
    @available(macOS 27.0, *)
    private func isIceButtonOnBar(screen: NSScreen) -> Bool {
        let display = CGDisplayBounds(screen.displayID)
        let strip = CGRect(x: display.minX, y: display.minY, width: display.width, height: 40)
        let items = MacOS27MenuBarItemProvider.ownMenuBarItems()
        guard let ice = items.first(matching: .visibleControlItem), strip.contains(ice.bounds) else {
            return false
        }
        for section in [MenuBarSection.Name.hidden, .alwaysHidden] where nativeHiding.isConcealing(section) {
            if
                let spacer = items.first(matching: .nativeBoundary(for: section)),
                strip.contains(spacer.bounds),
                spacer.bounds.minX >= ice.bounds.minX
            {
                return false
            }
        }
        return true
    }

    /// Returns the current frame of Ice's visible control item, read through
    /// Accessibility from Ice's own process.
    @available(macOS 27.0, *)
    private func currentIceButtonFrame() -> CGRect? {
        MacOS27MenuBarItemProvider.ownMenuBarItems().first(matching: .visibleControlItem)?.bounds
    }

    /// Applies the latest requested visibility once the given delay has passed.
    @available(macOS 27.0, *)
    private func scheduleDeferredNativeVisibilitySync(after delay: Duration) {
        guard deferredNativeVisibilityTask == nil else { return }
        deferredNativeVisibilityTask = Task { [weak self] in
            try? await Task.sleep(for: delay)
            guard let self else { return }
            deferredNativeVisibilityTask = nil
            syncNativeVisibility()
        }
    }

    /// Logs a macOS 27 visibility decision when it differs from the last one,
    /// so the periodic cache refresh doesn't repeat it every five seconds.
    private func logNativeVisibilityDecision(_ decision: String) {
        guard decision != lastNativeVisibilityDecision else { return }
        lastNativeVisibilityDecision = decision
        logger.notice("macOS 27 visibility: \(decision, privacy: .public)")
    }

    private func cancelNativeConcealment() {
        guard nativeConcealmentTask != nil else { return }
        nativeVisibilityGeneration &+= 1
        nativeConcealmentTask?.cancel()
        nativeConcealmentTask = nil
    }

    /// Even a third-party-to-third-party drag depends on the current native
    /// row: withdrawing or resizing Ice's boundary would move its endpoints.
    /// Pin only the event sequence, not the asynchronous result verification.
    func beginNativeDrag() {
        nativeDragVisibility.beginDrag()
    }

    func endNativeDrag() {
        if nativeDragVisibility.endDrag() {
            syncNativeVisibility()
        }
    }

    /// Temporarily reveals items concealed for the Ice Bar, so one of them
    /// can be clicked where MenuBarAgent draws it.
    @available(macOS 27.0, *)
    func beginIceBarReveal() {
        iceBarRevealDepth += 1
        syncNativeVisibility()
    }

    /// Ends a temporary reveal started by `beginIceBarReveal()`.
    @available(macOS 27.0, *)
    func endIceBarReveal() {
        iceBarRevealDepth = max(0, iceBarRevealDepth - 1)
        syncNativeVisibility()
    }

    /// A click after Layout toggles the actual, currently expanded bar.
    func prepareForControlToggle() {
        guard #available(macOS 27.0, *) else { return }
        lastUserToggleTimestamp = .now
        needsUserActionToAlignBoundary = false
        guard macOS27Controller.isLayoutEditing else { return }
        for section in sections { section.controlItem.state = .showSection }
        macOS27Controller.endLayoutEditing()
    }

    /// Configures the internal observers for the manager.
    private func configureCancellables() {
        var c = Set<AnyCancellable>()

        NSApp.publisher(for: \.currentSystemPresentationOptions)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] options in
                guard let self else {
                    return
                }
                let hidden = options.contains(.hideMenuBar) || options.contains(.autoHideMenuBar)
                isMenuBarHiddenBySystem = hidden
            }
            .store(in: &c)

        if
            let hiddenSection = section(withName: .alwaysHidden),
            let window = hiddenSection.controlItem.window
        {
            window.publisher(for: \.frame)
                .map { $0.origin.y }
                .removeDuplicates()
                .receive(on: DispatchQueue.main)
                .sink { [weak self] _ in
                    guard
                        let self,
                        let isMenuBarHidden = Defaults.globalDomain["_HIHideMenuBar"] as? Bool
                    else {
                        return
                    }
                    isMenuBarHiddenBySystemUserDefaults = isMenuBarHidden
                }
                .store(in: &c)
        }

        // Handle the `focusedApp` rehide strategy.
        NSWorkspace.shared.publisher(for: \.frontmostApplication)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                guard #unavailable(macOS 27.0) else { return }
                if
                    let self,
                    let appState,
                    case .focusedApp = appState.settings.general.rehideStrategy,
                    let hiddenSection = section(withName: .hidden),
                    let screen = appState.hidEventManager.bestScreen(appState: appState),
                    !appState.hidEventManager.isMouseInsideMenuBar(appState: appState, screen: screen)
                {
                    Task {
                        try await Task.sleep(for: .seconds(0.1))
                        hiddenSection.hide()
                    }
                }
            }
            .store(in: &c)

        appState?.publisherForWindow(.settings)
            .sink { [weak self] window in
                self?.settingsWindow = window
            }
            .store(in: &c)

        // SwiftUI does not reliably send `onDisappear` when the Settings
        // window is merely ordered out. End Layout's temporary reveal from the
        // window lifecycle as well, so closing Layout cannot leave every item
        // exposed and consume the next Ice click as a state correction.
        $settingsWindow
            .removeNil()
            .flatMap { $0.publisher(for: \.isVisible) }
            .removeDuplicates()
            .receive(on: DispatchQueue.main)
            .sink { [weak self] isVisible in
                guard let self, !isVisible else { return }
                if #available(macOS 27.0, *), macOS27Controller.isLayoutEditing {
                    macOS27Controller.endLayoutEditing()
                }
            }
            .store(in: &c)

        $settingsWindow
            .removeNil()
            .flatMap { $0.publisher(for: \.isVisible) }
            .discardMerge(Timer.publish(every: 5, on: .main, in: .default).autoconnect())
            .receive(on: DispatchQueue.main)
            .sink { [weak self] in
                self?.updateAverageColorInfo()
            }
            .store(in: &c)

        // Hide application menus when a section is shown (if applicable).
        Publishers.MergeMany(sections.map { $0.controlItem.$state })
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                guard #unavailable(macOS 27.0) else { return }
                guard let self, let appState else {
                    return
                }

                // Don't continue if:
                //   * The "HideApplicationMenus" setting isn't enabled.
                //   * Using the Ice Bar.
                //   * The menu bar is hidden by the system.
                //   * The active space is fullscreen.
                //   * The settings window is visible.
                guard
                    appState.settings.advanced.hideApplicationMenus,
                    !appState.settings.general.useIceBar,
                    !isMenuBarHiddenBySystem,
                    !appState.activeSpace.isFullscreen,
                    !appState.navigationState.isSettingsPresented
                else {
                    return
                }

                if sections.contains(where: { $0.controlItem.state == .showSection }) {
                    guard let screen = NSScreen.main else {
                        return
                    }

                    // Get the application menu frame for the display.
                    guard let applicationMenuFrame = screen.getApplicationMenuFrame() else {
                        return
                    }

                    Task {
                        // Get all items.
                        var items = await MenuBarItem.getMenuBarItems(on: screen.displayID, option: .activeSpace)

                        // Filter the items down according to the currently enabled/shown sections.
                        if
                            let alwaysHiddenSection = self.section(withName: .alwaysHidden),
                            alwaysHiddenSection.isEnabled
                        {
                            if alwaysHiddenSection.controlItem.state == .hideSection {
                                if let alwaysHiddenControlItem = items.firstIndex(matching: .alwaysHiddenControlItem).map({ items.remove(at: $0) }) {
                                    items.trimPrefix { $0.bounds.maxX <= alwaysHiddenControlItem.bounds.minX }
                                }
                            }
                        } else {
                            if let hiddenControlItem = items.firstIndex(matching: .hiddenControlItem).map({ items.remove(at: $0) }) {
                                items.trimPrefix { $0.bounds.maxX <= hiddenControlItem.bounds.minX }
                            }
                        }

                        // Get the leftmost item on the screen.
                        guard let leftmostItem = items.min(by: { $0.bounds.minX < $1.bounds.minX }) else {
                            return
                        }

                        // If the minX of the item is less than or equal to the maxX of the
                        // application menu frame, activate the app to hide the menu.
                        if leftmostItem.bounds.minX <= applicationMenuFrame.maxX {
                            self.hideApplicationMenus()
                        }
                    }
                } else if isHidingApplicationMenus {
                    showApplicationMenus()
                }
            }
            .store(in: &c)

        cancellables = c
    }

    /// Updates the ``averageColorInfo`` property with the current average color
    /// of the menu bar.
    ///
    /// The window list and the capture take long enough to be felt in Ice's
    /// own interface, and this runs on a timer while the settings window is
    /// open, so the work happens off the main thread.
    func updateAverageColorInfo() {
        guard
            let settingsWindow,
            settingsWindow.isVisible,
            let screen = settingsWindow.screen
        else {
            return
        }
        let displayID = screen.displayID
        averageColorTask?.cancel()
        averageColorTask = Task { [weak self] in
            let info = await Task.detached(priority: .utility) {
                let windows = WindowInfo.createWindows(option: .onScreen)
                guard
                    let menuBarWindow = WindowInfo.menuBarWindow(from: windows, for: displayID),
                    let wallpaperWindow = WindowInfo.wallpaperWindow(from: windows, for: displayID),
                    let image = ScreenCapture.captureWindows(
                        with: [menuBarWindow.windowID, wallpaperWindow.windowID],
                        screenBounds: withMutableCopy(of: wallpaperWindow.bounds) { $0.size.height = 1 },
                        option: .nominalResolution
                    ),
                    let color = image.averageColor(option: .ignoreAlpha)
                else {
                    return nil as MenuBarAverageColorInfo?
                }
                return MenuBarAverageColorInfo(color: color, source: .menuBarWindow)
            }.value
            guard let self, let info, !Task.isCancelled else {
                return
            }
            if averageColorInfo != info {
                averageColorInfo = info
            }
        }
    }

    /// Returns a Boolean value that indicates whether the given display
    /// has a valid menu bar.
    func hasValidMenuBar(in windows: [WindowInfo], for display: CGDirectDisplayID) -> Bool {
        guard
            let window = WindowInfo.menuBarWindow(from: windows, for: display),
            let element = AXHelpers.element(at: window.bounds.origin)
        else {
            return false
        }
        return AXHelpers.role(for: element) == .menuBar
    }

    /// Shows the secondary context menu.
    func showSecondaryContextMenu(at point: CGPoint) {
        let menu = NSMenu(title: "Ice")

        let editAppearanceItem = NSMenuItem(
            title: "Edit Menu Bar Appearance…",
            action: #selector(showAppearanceEditorPanel),
            keyEquivalent: ""
        )
        editAppearanceItem.target = self
        menu.addItem(editAppearanceItem)

        menu.addItem(.separator())

        let settingsItem = NSMenuItem(
            title: "Ice Settings…",
            action: #selector(AppDelegate.openSettingsWindow),
            keyEquivalent: ","
        )
        menu.addItem(settingsItem)

        menu.popUp(positioning: nil, at: point, in: nil)
    }

    /// Hides the application menus.
    func hideApplicationMenus() {
        guard let appState else {
            logger.error("Error hiding application menus: Missing app state")
            return
        }
        logger.info("Hiding application menus")
        appState.activate(withPolicy: .regular)
        isHidingApplicationMenus = true
    }

    /// Shows the application menus.
    func showApplicationMenus() {
        guard let appState else {
            logger.error("Error showing application menus: Missing app state")
            return
        }
        logger.info("Showing application menus")
        appState.deactivate(withPolicy: .accessory)
        isHidingApplicationMenus = false
    }

    /// Toggles the visibility of the application menus.
    func toggleApplicationMenus() {
        if isHidingApplicationMenus {
            showApplicationMenus()
        } else {
            hideApplicationMenus()
        }
    }

    /// Shows the appearance editor panel.
    @objc private func showAppearanceEditorPanel() {
        guard let screen = MenuBarAppearanceEditorPanel.defaultScreen else {
            return
        }
        appearanceEditorPanel.show(on: screen)
    }

    /// Returns the menu bar section with the given name.
    func section(withName name: MenuBarSection.Name) -> MenuBarSection? {
        sections.first { $0.name == name }
    }

    /// Returns the control item for the menu bar section with the given name.
    func controlItem(withName name: MenuBarSection.Name) -> ControlItem? {
        section(withName: name)?.controlItem
    }
}

// MARK: - MenuBarAverageColorInfo

/// Information for the average color of the menu bar.
struct MenuBarAverageColorInfo: Hashable {
    /// Sources used to compute the average color of the menu bar.
    enum Source: Hashable {
        case menuBarWindow
        case desktopWallpaper
    }

    /// The average color of the menu bar
    var color: CGColor

    /// The source used to compute the color.
    var source: Source

    /// The brightness of the menu bar's color.
    var brightness: CGFloat { color.brightness ?? 0 }

    /// A Boolean value that indicates whether the menu bar has a
    /// bright color.
    ///
    /// This value is `true` if ``brightness`` is above `0.67`. At
    /// the time of writing, if this value is `true`, the menu bar
    /// draws its items with a darker appearance.
    var isBright: Bool { brightness > 0.67 }
}
