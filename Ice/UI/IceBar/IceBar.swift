//
//  IceBar.swift
//  Ice
//

import Combine
import SwiftUI

// MARK: - IceBarPanel

final class IceBarPanel: NSPanel {
    private weak var appState: AppState?

    private(set) var currentSection: MenuBarSection.Name?

    private lazy var colorManager = IceBarColorManager(iceBarPanel: self)

    private var cancellables = Set<AnyCancellable>()

    private var axActivationTask: Task<Void, Never>?

    /// Automatic rehide must not collapse originals while their menu is in use.
    private(set) var isActivatingAXItem = false

    init(appState: AppState) {
        super.init(
            contentRect: .zero,
            styleMask: [.nonactivatingPanel, .fullSizeContentView, .borderless],
            backing: .buffered,
            defer: false
        )
        self.appState = appState
        self.title = "Ice Bar"
        self.titlebarAppearsTransparent = true
        self.isMovableByWindowBackground = true
        self.allowsToolTipsWhenApplicationIsInactive = true
        self.isFloatingPanel = true
        self.animationBehavior = .none
        self.backgroundColor = .clear
        self.hasShadow = false
        self.level = .mainMenu + 1
        self.collectionBehavior = [.fullScreenAuxiliary, .ignoresCycle, .moveToActiveSpace]
    }

    func performSetup() {
        configureCancellables()
    }

    private func configureCancellables() {
        var c = Set<AnyCancellable>()

        // Close the panel when the active space changes, or when the screen parameters change.
        Publishers.Merge(
            NSWorkspace.shared.notificationCenter.publisher(for: NSWorkspace.activeSpaceDidChangeNotification),
            NotificationCenter.default.publisher(for: NSApplication.didChangeScreenParametersNotification)
        )
        .sink { [weak self] _ in
            self?.close()
        }
        .store(in: &c)

        if
            let section = appState?.menuBarManager.section(withName: .hidden),
            let window = section.controlItem.window
        {
            window.publisher(for: \.frame)
                .debounce(for: 0.1, scheduler: DispatchQueue.main)
                .sink { [weak self, weak window] _ in
                    guard
                        let self,
                        let appState,
                        // Only continue if the menu bar is automatically hidden, as Ice
                        // can't currently display its menu bar items.
                        appState.menuBarManager.isMenuBarHiddenBySystemUserDefaults,
                        // windowNumber is Int and traps on overflow with the non-failable
                        // initializer on macOS 26 (see jordanbaird/Ice#580, #977).
                        // Degrade to nil instead of crashing; call sites handle nil.
                        let info = window.map(\.windowNumber).flatMap(CGWindowID.init(exactly:)).flatMap(WindowInfo.init(windowID:)),
                        // Window being offscreen means the menu bar is currently hidden.
                        // Close the bar, as things will start to look weird if we don't.
                        !info.isOnScreen
                    else {
                        return
                    }
                    close()
                }
                .store(in: &c)
        }

        // Update the panel's origin whenever its size changes.
        publisher(for: \.frame)
            .map(\.size)
            .removeDuplicates()
            .sink { [weak self] _ in
                guard
                    let self,
                    let screen
                else {
                    return
                }
                updateOrigin(for: screen)
            }
            .store(in: &c)

        cancellables = c
    }

    private func updateOrigin(for screen: NSScreen) {
        guard let appState else {
            return
        }

        func getOrigin(for iceBarLocation: IceBarLocation) -> CGPoint {
            let menuBarHeight = screen.getMenuBarHeight() ?? 0
            let originY = ((screen.frame.maxY - 1) - menuBarHeight) - frame.height

            var originForRightOfScreen: CGPoint {
                CGPoint(x: screen.frame.maxX - frame.width, y: originY)
            }

            switch iceBarLocation {
            case .dynamic:
                if appState.eventManager.isMouseInsideEmptyMenuBarSpace {
                    return getOrigin(for: .mousePointer)
                }
                return getOrigin(for: .iceIcon)
            case .mousePointer:
                guard let location = MouseCursor.locationAppKit else {
                    return getOrigin(for: .iceIcon)
                }

                let lowerBound = screen.frame.minX
                let upperBound = screen.frame.maxX - frame.width

                guard lowerBound <= upperBound else {
                    return originForRightOfScreen
                }

                return CGPoint(x: (location.x - frame.width / 2).clamped(to: lowerBound...upperBound), y: originY)
            case .iceIcon:
                let lowerBound = screen.frame.minX
                let upperBound = screen.frame.maxX - frame.width

                guard
                    lowerBound <= upperBound,
                    let section = appState.menuBarManager.section(withName: .visible),
                    // Bridging.getWindowFrame is more reliable than ControlItem.windowFrame,
                    // i.e. if the control item is offscreen. Fall back to our own window's
                    // frame when the system no longer exposes a per-item window ID.
                    let itemFrame = section.controlItem.windowID.flatMap({ Bridging.getWindowFrame(for: $0) })
                        ?? section.controlItem.windowFrame
                else {
                    return originForRightOfScreen
                }

                return CGPoint(x: (itemFrame.midX - frame.width / 2).clamped(to: lowerBound...upperBound), y: originY)
            }
        }

        setFrameOrigin(getOrigin(for: appState.settingsManager.generalSettingsManager.iceBarLocation))
    }

    /// Restores hidden originals before AXPress; parked status items may acknowledge a press
    /// without opening anything. Only transient state is changed, and menus stay revealed
    /// until they close. A later activation waits for the previous reveal to clean up.
    func activateAXItem(_ item: MenuBarItemAXDiscovery.AXMenuBarItem) {
        guard let appState else {
            return
        }
        close()
        let previous = axActivationTask
        previous?.cancel()
        axActivationTask = Task { @MainActor in
            await previous?.value
            guard !Task.isCancelled else {
                return
            }

            isActivatingAXItem = true
            let sections = appState.menuBarManager.sections.filter {
                $0.isEnabled && $0.controlItem.state == .hideItems
            }
            let revealed = sections.map { section in
                section.setState(.showItems, persist: false)
                return (section: section, revision: section.stateRevision)
            }
            defer {
                for entry in revealed where entry.section.stateRevision == entry.revision {
                    entry.section.setState(.hideItems, persist: false)
                }
                isActivatingAXItem = false
                for section in appState.menuBarManager.sections where !section.isHidden {
                    section.startRehideChecks()
                }
            }

            do {
                // Match the native section toggle's animation interval before pressing.
                try await Task.sleep(for: .milliseconds(250))
                let previousWindows = Set(WindowInfo.getOnScreenWindows().map(\.windowID))
                let acknowledged = await Task.detached(priority: .userInitiated) {
                    MenuBarItemAXDiscovery.press(item)
                }.value

                // AX success alone is not evidence of a menu. Conversely, a modal menu
                // can open while the request times out, so check even after an AX error.
                func hasOpenMenu() -> Bool {
                    WindowInfo.getOnScreenWindows().contains { window in
                        !previousWindows.contains(window.windowID) &&
                        !window.frame.isEmpty && !window.isMenuBarItem &&
                        window.layer >= CGWindowLevelForKey(.mainMenuWindow) &&
                        (window.ownerPID == item.pid ||
                            NSRunningApplication(processIdentifier: window.ownerPID)?.bundleIdentifier == "com.apple.controlcenter")
                    }
                }
                var observedMenu = false
                for _ in 0..<10 {
                    try Task.checkCancellation()
                    if hasOpenMenu() {
                        observedMenu = true
                        break
                    }
                    try await Task.sleep(for: .milliseconds(100))
                }
                guard observedMenu else {
                    Logger.iceBar.error("axActivation no visible menu pid=\(item.pid) acknowledged=\(acknowledged)")
                    return
                }
                Logger.iceBar.info("axActivation observed menu pid=\(item.pid)")
                // Keep the reveal while any popup remains, including a parent whose
                // frontmost submenu closed or a replacement popup with a new window ID.
                while hasOpenMenu() {
                    try await Task.sleep(for: .milliseconds(150))
                }
            } catch {
                // Cancellation restores the reveal through defer without another click.
            }
        }
    }

    func show(section: MenuBarSection.Name, on screen: NSScreen) async {
        guard let appState else {
            return
        }

        // Important that we set the navigation state and current section before updating the cache.
        appState.navigationState.isIceBarPresented = true
        currentSection = section

        await appState.itemManager.cacheItemsIfNeeded()

        if ScreenCapture.cachedCheckPermissions() {
            await appState.imageCache.updateCache()
        }

        // A newer show() may have claimed the panel while waiting for the cache —
        // bail out without closing (the panel now belongs to that show).
        guard currentSection == section else {
            return
        }

        contentView = IceBarHostingView(appState: appState, colorManager: colorManager, screen: screen, section: section) { [weak self] in
            self?.close()
        }

        updateOrigin(for: screen)

        // Color manager must be updated after updating the panel's origin, but before it is shown.
        //
        // Color manager handles frame changes automatically, but does so on the main queue, so we
        // need to update manually once before showing the panel to prevent the color from flashing.
        colorManager.updateAllProperties(with: frame, screen: screen)

        orderFrontRegardless()
    }

    override func close() {
        super.close()
        contentView = nil
        currentSection = nil
        appState?.navigationState.isIceBarPresented = false
    }
}

// MARK: - IceBarHostingView

private final class IceBarHostingView: NSHostingView<AnyView> {
    override var safeAreaInsets: NSEdgeInsets {
        NSEdgeInsets()
    }

    init(
        appState: AppState,
        colorManager: IceBarColorManager,
        screen: NSScreen,
        section: MenuBarSection.Name,
        closePanel: @escaping () -> Void
    ) {
        super.init(
            rootView: IceBarContentView(screen: screen, section: section, closePanel: closePanel)
                .environmentObject(appState)
                .environmentObject(appState.imageCache)
                .environmentObject(appState.itemManager)
                .environmentObject(appState.menuBarManager)
                .environmentObject(colorManager)
                .erasedToAnyView()
        )
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    @available(*, unavailable)
    required init(rootView: AnyView) {
        fatalError("init(rootView:) has not been implemented")
    }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool {
        return true
    }
}

// MARK: - SplitPillShape

/// Stadium pill mirroring the split-shape trailing pill geometry in
/// `shapePath` (rect body + oval/square end caps), so the Ice Bar clips and
/// borders exactly like the menu bar pill.
private struct SplitPillShape: InsettableShape {
    var leadingEndCap: MenuBarEndCap
    var trailingEndCap: MenuBarEndCap
    var cornerRadiusFactor: Double = 1
    var insetAmount: CGFloat = 0

    func path(in rect: CGRect) -> Path {
        let r = rect.insetBy(dx: insetAmount, dy: insetAmount)
        guard r.height > 0, r.width > 0 else {
            return Path()
        }
        let factor = CGFloat(cornerRadiusFactor).clamped(to: 0...1)
        // Partial rounding: per-side radii via uneven rounded rect.
        if factor < 0.999 {
            let radius = r.height / 2 * factor
            let leadingRadius: CGFloat = leadingEndCap == .round ? radius : 0
            let trailingRadius: CGFloat = trailingEndCap == .round ? radius : 0
            return UnevenRoundedRectangle(
                topLeadingRadius: leadingRadius,
                bottomLeadingRadius: leadingRadius,
                bottomTrailingRadius: trailingRadius,
                topTrailingRadius: trailingRadius,
                style: .circular
            ).path(in: r)
        }
        var path = Path()
        path.addRect(CGRect(x: r.minX + r.height / 2, y: r.minY, width: max(0, r.width - r.height), height: r.height))
        switch leadingEndCap {
        case .square:
            path.addRect(CGRect(origin: r.origin, size: CGSize(width: r.height, height: r.height)))
        case .round:
            path.addEllipse(in: CGRect(origin: r.origin, size: CGSize(width: r.height, height: r.height)))
        }
        switch trailingEndCap {
        case .square:
            path.addRect(CGRect(x: r.maxX - r.height, y: r.minY, width: r.height, height: r.height))
        case .round:
            path.addEllipse(in: CGRect(x: r.maxX - r.height, y: r.minY, width: r.height, height: r.height))
        }
        return path
    }

    func inset(by amount: CGFloat) -> SplitPillShape {
        var copy = self
        copy.insetAmount += amount
        return copy
    }
}

// MARK: - IceBarContentView

private struct IceBarContentView: View {
    @EnvironmentObject var appState: AppState
    @EnvironmentObject var colorManager: IceBarColorManager
    @EnvironmentObject var itemManager: MenuBarItemManager
    @EnvironmentObject var imageCache: MenuBarItemImageCache
    @EnvironmentObject var menuBarManager: MenuBarManager
    @State private var frame = CGRect.zero
    @State private var scrollIndicatorsFlashTrigger = 0
    @State private var axRows = [AXRowItem]()
    @State private var hasAXPermission = MenuBarItemAXDiscovery.isTrusted()
    @State private var isLoadingAXRows = false

    let screen: NSScreen
    let section: MenuBarSection.Name
    let closePanel: () -> Void

    private var items: [MenuBarItem] {
        itemManager.itemCache.managedItems(for: section)
    }

    private var configuration: MenuBarAppearanceConfigurationV2 {
        appState.appearanceManager.configuration
    }

    private var horizontalPadding: CGFloat {
        configuration.hasRoundedShape ? 7 : 5
    }

    private var verticalPadding: CGFloat {
        screen.hasNotch ? 0 : 2
    }

    private var contentHeight: CGFloat? {
        guard let menuBarHeight = imageCache.menuBarHeight ?? screen.getMenuBarHeight() else {
            return nil
        }
        if configuration.shapeKind != .none && configuration.isInset && screen.hasNotch {
            return menuBarHeight - appState.appearanceManager.menuBarInsetAmount * 2
        }
        return menuBarHeight
    }

    private var clipShape: AnyInsettableShape {
        barShape
    }

    /// Whether the bar mirrors the split-shape trailing pill (same end caps,
    /// tint opacity, inside border and shadow).
    private var isSplitPill: Bool {
        configuration.shapeKind == .split
    }

    private var barShape: AnyInsettableShape {
        // Same stadium shape as the split's trailing pill: rectangular body
        // plus 2 oval/rectangular end caps (mirror `shapePath`).
        let trailing = configuration.splitShapeInfo.trailing
        if isSplitPill {
            return AnyInsettableShape(
                SplitPillShape(
                    leadingEndCap: trailing.leadingEndCap,
                    trailingEndCap: trailing.trailingEndCap,
                    cornerRadiusFactor: configuration.cornerRadius
                )
            )
        } else if configuration.hasRoundedShape {
            if configuration.cornerRadius >= 0.999 {
                return AnyInsettableShape(Capsule())
            }
            return AnyInsettableShape(
                RoundedRectangle(
                    cornerRadius: max(0, frame.height / 2 * CGFloat(configuration.cornerRadius)),
                    style: .continuous
                )
            )
        } else {
            return AnyInsettableShape(RoundedRectangle(cornerRadius: frame.height / 5, style: .continuous))
        }
    }

    /// Bar tint opacity: matches the split, otherwise keeps the old 0.2.
    private var barTintOpacity: Double {
        isSplitPill ? configuration.current.tintOpacity : 0.2
    }

    @ViewBuilder
    private var splitBorderOverlay: some View {
        // Mirror MenuBarTintView HACK: stroke at double width then trim the outer half
        // via the clipShape right after → border sits neatly inside the pill.
        if isSplitPill, configuration.current.hasBorder {
            barShape.stroke(
                Color(cgColor: configuration.current.borderColor),
                lineWidth: CGFloat(configuration.current.borderWidth) * 2
            )
        }
    }

    private var barShadowColor: Color {
        if isSplitPill {
            configuration.current.hasShadow ? .black.opacity(0.5) : .clear
        } else {
            .black.opacity(shadowOpacity)
        }
    }

    private var barShadowRadius: CGFloat {
        isSplitPill ? 5 : 2.5
    }

    private var shadowOpacity: CGFloat {
        configuration.current.hasShadow ? 0.5 : 0.33
    }

    var body: some View {
        ZStack {
            content
                .frame(height: contentHeight)
                .padding(.horizontal, horizontalPadding)
                .padding(.vertical, verticalPadding)
                .layoutBarStyle(appState: appState, averageColorInfo: colorManager.colorInfo, tintOpacity: barTintOpacity, useLiveBlur: isSplitPill)
                .foregroundStyle(colorManager.colorInfo?.color.brightness ?? 0 > 0.67 ? .black : .white)
                .overlay(splitBorderOverlay)
                .clipShape(clipShape)
                .shadow(color: barShadowColor, radius: barShadowRadius)

            if configuration.current.hasBorder, !isSplitPill {
                clipShape
                    .inset(by: configuration.current.borderWidth / 2)
                    .stroke(lineWidth: configuration.current.borderWidth)
                    .foregroundStyle(Color(cgColor: configuration.current.borderColor))
            }
        }
        .padding(5)
        .frame(maxWidth: imageCache.screen?.frame.width)
        .fixedSize()
        .onFrameChange(update: $frame)
    }

    @ViewBuilder
    private var content: some View {
        if itemManager.isItemDiscoveryUnavailable {
            // macOS 27+: CGS no longer has per-item windows — show the app icon and
            // press via Accessibility instead of window snapshots + temp-show.
            axFallbackView
                .task {
                    await loadAXRows()
                }
        } else if !ScreenCapture.cachedCheckPermissions() {
            HStack {
                Text("The Ice Bar requires screen recording permissions.")

                Button {
                    closePanel()
                    appState.navigationState.settingsNavigationIdentifier = .advanced
                    appState.appDelegate?.openSettingsWindow()
                } label: {
                    Text("Open Ice Settings")
                }
                .buttonStyle(.plain)
                .foregroundStyle(.link)
            }
            .padding(.horizontal, 10)
        } else if menuBarManager.isMenuBarHiddenBySystemUserDefaults {
            Text("Ice cannot display menu bar items for automatically hidden menu bars")
                .padding(.horizontal, 10)
        } else if imageCache.cacheFailed(for: section) {
            Text("Unable to display menu bar items")
                .padding(.horizontal, 10)
        } else {
            ScrollView(.horizontal) {
                HStack(spacing: 0) {
                    ForEach(items, id: \.windowID) { item in
                        IceBarItemView(item: item, closePanel: closePanel)
                    }
                }
            }
            .environment(\.isScrollEnabled, frame.width == imageCache.screen?.frame.width)
            .defaultScrollAnchor(.trailing)
            .scrollIndicatorsFlash(trigger: scrollIndicatorsFlashTrigger)
            .task {
                scrollIndicatorsFlashTrigger += 1
            }
        }
    }

    // MARK: - AX fallback (macOS 27+)

    /// Icon row for the Ice Bar when CGS no longer has per-item windows.
    private struct AXRowItem: Identifiable {
        /// Stable ID across scans (not a random UUID) so
        /// SwiftUI diffs smoothly.
        let id: String
        let item: MenuBarItemAXDiscovery.AXMenuBarItem
        let title: String?
        let displayName: String
        let systemImage: String?
        let appIcon: NSImage?
        /// X center (AX coordinates) for visibility filtering, nil when the frame is unreadable.
        let midX: CGFloat?
    }

    private static let accessibilitySettingsURL = URL(
        string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility"
    )!

    @ViewBuilder
    private var axFallbackView: some View {
        if !hasAXPermission {
            HStack {
                Text("The Ice Bar requires accessibility permission.")

                Button {
                    NSWorkspace.shared.open(Self.accessibilitySettingsURL)
                } label: {
                    Text("Open System Settings")
                }
                .buttonStyle(.plain)
                .foregroundStyle(.link)

                Button {
                    hasAXPermission = MenuBarItemAXDiscovery.isTrusted()
                    if hasAXPermission {
                        Task {
                            await loadAXRows()
                        }
                    }
                } label: {
                    Text("Check Again")
                }
                .buttonStyle(.plain)
                .foregroundStyle(.link)
            }
            .padding(.horizontal, 10)
        } else if isLoadingAXRows && axRows.isEmpty {
            ProgressView()
                .padding(.horizontal, 10)
        } else if axRows.isEmpty {
            Text("Unable to display menu bar items")
                .padding(.horizontal, 10)
        } else {
            ScrollView(.horizontal) {
                HStack(spacing: 0) {
                    ForEach(axRows) { row in
                        axRowView(row)
                    }
                }
            }
            .defaultScrollAnchor(.trailing)
            .scrollIndicatorsFlash(trigger: scrollIndicatorsFlashTrigger)
            .task {
                scrollIndicatorsFlashTrigger += 1
            }
        }
    }

    @ViewBuilder
    private func axRowView(_ row: AXRowItem) -> some View {
        Button {
            press(row)
        } label: {
            if let systemName = row.systemImage {
                Image(systemName: systemName)
                    .font(.system(size: 16))
                    .frame(minWidth: 28, minHeight: 22)
            } else if let icon = row.appIcon {
                Image(nsImage: icon)
                    .resizable()
                    .scaledToFit()
                    .frame(width: 24, height: 22)
            } else if let title = row.title, !title.isEmpty {
                Text(title)
                    .lineLimit(1)
                    .padding(.horizontal, 6)
            } else {
                Text(row.displayName)
                    .lineLimit(1)
                    .padding(.horizontal, 6)
            }
        }
        .buttonStyle(.plain)
        .contentShape(Rectangle())
        .help(row.displayName)
        .accessibilityLabel(row.displayName)
        .accessibilityAction(named: "press") {
            press(row)
        }
    }

    /// Scans AX for the open section, filtering with the same divider-based
    /// classification as Menu Bar Layout. If the dividers haven't laid out yet
    /// (all nil), shows everything instead of returning an empty bar.
    ///
    /// Scans up to 3 times, ~0.8s apart: on macOS 27 the menubar layout needs
    /// time for the dividers to settle after showing a section; the first scan
    /// may hit the garbage frame of a parking spacer.
    private func loadAXRows() async {
        guard !isLoadingAXRows else {
            return
        }
        isLoadingAXRows = true
        defer {
            isLoadingAXRows = false
        }

        hasAXPermission = MenuBarItemAXDiscovery.isTrusted()
        guard hasAXPermission else {
            return
        }

        for attempt in 0..<3 {
            await scanAXRowsOnce(attempt: attempt)
            if !axRows.isEmpty || Task.isCancelled {
                return
            }
            try? await Task.sleep(for: .milliseconds(800))
        }
    }

    /// One AX scan: lists items, filters by section, builds rows.
    private func scanAXRowsOnce(attempt: Int) async {
        // NSWorkspace must be read on main; heavy discovery runs in the background. Divider
        // positions are also looked up in the background via AX (same coordinate space as axFrame).
        let apps = NSWorkspace.shared.runningApplications
        let wantedSection = section

        let (found, axDividers) = await Task.detached(priority: .userInitiated) {
            (
                MenuBarItemAXDiscovery.discoverItems(in: apps),
                MenuBarItemAXDiscovery.dividerFrames()
            )
        }.value

        // Prefer dividers via AX, but EXCLUDE the garbage frame of a parking spacer
        // (hundreds of pt wide at the bottom of the screen) — if its minX (e.g. 7.0) leaks
        // into classification, every item drifts to Visible and the bar ends up empty.
        // button.window.frame on macOS 27 also returns the spacer rect (minX = 0),
        // so only use it as a fallback when AX is missing and the value is valid (minX > 0).
        func settledMinX(_ frame: CGRect?) -> CGFloat? {
            frame.flatMap { MenuBarItemAXDiscovery.isSettledDividerFrame($0) ? $0.minX : nil }
        }
        func saneMinX(_ value: CGFloat?) -> CGFloat? {
            value.flatMap { $0 > 0 ? $0 : nil }
        }
        let hiddenX = settledMinX(axDividers.hidden)
            ?? saneMinX(menuBarManager.section(withName: .hidden)?.controlItem.window?.frame.minX)
        let alwaysHiddenX = settledMinX(axDividers.alwaysHidden)
            ?? saneMinX(menuBarManager.section(withName: .alwaysHidden)?.controlItem.window?.frame.minX)

        func kind(centerX: CGFloat?) -> MenuBarItemAXDiscovery.SectionKind {
            MenuBarItemAXDiscovery.classify(centerX: centerX, hiddenDividerX: hiddenX, alwaysHiddenDividerX: alwaysHiddenX)
        }
        let dividersMissing = hiddenX == nil && alwaysHiddenX == nil

        // Stable IDs across scans so SwiftUI doesn't redraw the whole list.
        var idCounts = [String: Int]()
        func stableID(for base: String) -> String {
            let n = idCounts[base, default: 0]
            idCounts[base] = n + 1
            return n == 0 ? base : "\(base)#\(n)"
        }

        // Discovery returns items by name; re-sort left→right as on the menubar.
        let ordered = found.sorted {
            ($0.axFrame?.midX ?? .greatestFiniteMagnitude) < ($1.axFrame?.midX ?? .greatestFiniteMagnitude)
        }
        var icons = [pid_t: NSImage]()
        var rows = [AXRowItem]()
        for item in ordered {
            // The bar currently merges hidden + alwaysHidden (excluding visible): dividers
            // while the spacer is expanding aren't reliable enough to split the 2 sections,
            // and the user intent is a single bar for all hidden apps.
            if !dividersMissing, kind(centerX: item.axFrame?.midX) == .visible {
                continue
            }
            // Same icon selection as Menu Bar Layout: familiar system extras
            // use SF Symbols (a PID-based icon would yield the generic MenuBarAgent icon).
            let systemImage = MenuBarItemAXDiscovery.systemImageName(forIdentifier: item.identifier)
            if systemImage == nil, icons[item.pid] == nil {
                if item.bundleID == "com.apple.TextInputMenuAgent" {
                    icons[item.pid] = MenuBarItemAXDiscovery.inputSourceIcon()
                } else {
                    icons[item.pid] = NSRunningApplication(processIdentifier: item.pid)?.icon
                }
            }
            rows.append(
                AXRowItem(
                    id: stableID(for: "ax:\(item.pid):\(item.bundleID ?? ""):\(item.identifier ?? ""):\(item.title ?? "")"),
                    item: item,
                    title: item.title,
                    displayName: item.displayName,
                    systemImage: systemImage,
                    appIcon: icons[item.pid],
                    midX: item.axFrame?.midX
                )
            )
        }
        // Expanding spacer (garbage divider frames): drop items already visible in the
        // trailing pill region — the user already sees them on the menubar. Only filter
        // when both dividers are missing; when a divider is still usable, classify by section
        // as before. Skip fullscreen (pill isn't drawn, width is stale).
        if dividersMissing,
           !appState.isActiveSpaceFullscreen,
           let trailingWidth = MenuBarOverlayPanelContentView.currentTrailingVisibleWidth(for: screen.displayID),
           trailingWidth > 0, trailingWidth < screen.frame.width
        {
            let visibleMinX = screen.frame.maxX - trailingWidth
            rows.removeAll { ($0.midX ?? .greatestFiniteMagnitude) >= visibleMinX - 4 }
        }
        axRows = rows
        Logger.iceBar.info("axScan done wanted=\(wantedSection) attempt=\(attempt) found=\(found.count) rows=\(rows.count) dividersMissing=\(dividersMissing)")
    }

    /// The panel owns the activation task after closing and releasing this view.
    private func press(_ row: AXRowItem) {
        Logger.iceBar.info("axPress requested pid=\(row.item.pid) element=\(CFHash(row.item.element)) hasIdentifier=\(row.item.identifier != nil) hasTitle=\(row.item.title != nil)")
        menuBarManager.iceBarPanel.activateAXItem(row.item)
    }
}

// MARK: - IceBarItemView

private struct IceBarItemView: View {
    @EnvironmentObject var imageCache: MenuBarItemImageCache
    @EnvironmentObject var itemManager: MenuBarItemManager

    let item: MenuBarItem
    let closePanel: () -> Void

    private var leftClickAction: () -> Void {
        return { [weak itemManager] in
            guard let itemManager else {
                return
            }
            closePanel()
            Task {
                try? await Task.sleep(for: .milliseconds(25))
                itemManager.tempShowItem(item, clickWhenFinished: true, mouseButton: .left)
            }
        }
    }

    private var rightClickAction: () -> Void {
        return { [weak itemManager] in
            guard let itemManager else {
                return
            }
            closePanel()
            Task {
                try? await Task.sleep(for: .milliseconds(25))
                itemManager.tempShowItem(item, clickWhenFinished: true, mouseButton: .right)
            }
        }
    }

    private var image: NSImage? {
        guard
            let image = imageCache.images[item.info],
            let screen = imageCache.screen
        else {
            return nil
        }
        let size = CGSize(
            width: CGFloat(image.width) / screen.backingScaleFactor,
            height: CGFloat(image.height) / screen.backingScaleFactor
        )
        return NSImage(cgImage: image, size: size)
    }

    var body: some View {
        if let image {
            Image(nsImage: image)
                .contentShape(Rectangle())
                .overlay {
                    IceBarItemClickView(item: item, leftClickAction: leftClickAction, rightClickAction: rightClickAction)
                }
                .accessibilityLabel(item.displayName)
                .accessibilityAction(named: "left click", leftClickAction)
                .accessibilityAction(named: "right click", rightClickAction)
        }
    }
}

// MARK: - IceBarItemClickView

private struct IceBarItemClickView: NSViewRepresentable {
    private final class Represented: NSView {
        let item: MenuBarItem

        let leftClickAction: () -> Void
        let rightClickAction: () -> Void

        private var lastLeftMouseDownDate = Date.now
        private var lastRightMouseDownDate = Date.now

        private var lastLeftMouseDownLocation = CGPoint.zero
        private var lastRightMouseDownLocation = CGPoint.zero

        init(item: MenuBarItem, leftClickAction: @escaping () -> Void, rightClickAction: @escaping () -> Void) {
            self.item = item
            self.leftClickAction = leftClickAction
            self.rightClickAction = rightClickAction
            super.init(frame: .zero)
            self.toolTip = item.displayName
        }

        @available(*, unavailable)
        required init?(coder: NSCoder) {
            fatalError("init(coder:) has not been implemented")
        }

        private func absoluteDistance(_ p1: CGPoint, _ p2: CGPoint) -> CGFloat {
            hypot(p1.x - p2.x, p1.y - p2.y).magnitude
        }

        override func mouseDown(with event: NSEvent) {
            super.mouseDown(with: event)
            lastLeftMouseDownDate = .now
            lastLeftMouseDownLocation = NSEvent.mouseLocation
        }

        override func rightMouseDown(with event: NSEvent) {
            super.rightMouseDown(with: event)
            lastRightMouseDownDate = .now
            lastRightMouseDownLocation = NSEvent.mouseLocation
        }

        override func mouseUp(with event: NSEvent) {
            super.mouseUp(with: event)
            guard
                Date.now.timeIntervalSince(lastLeftMouseDownDate) < 0.5,
                absoluteDistance(lastLeftMouseDownLocation, NSEvent.mouseLocation) < 5
            else {
                return
            }
            leftClickAction()
        }

        override func rightMouseUp(with event: NSEvent) {
            super.rightMouseUp(with: event)
            guard
                Date.now.timeIntervalSince(lastRightMouseDownDate) < 0.5,
                absoluteDistance(lastRightMouseDownLocation, NSEvent.mouseLocation) < 5
            else {
                return
            }
            rightClickAction()
        }
    }

    let item: MenuBarItem

    let leftClickAction: () -> Void
    let rightClickAction: () -> Void

    func makeNSView(context: Context) -> NSView {
        Represented(item: item, leftClickAction: leftClickAction, rightClickAction: rightClickAction)
    }

    func updateNSView(_ nsView: NSView, context: Context) { }
}

// MARK: - Logger

private extension Logger {
    static let iceBar = Logger(category: "IceBar")
}
