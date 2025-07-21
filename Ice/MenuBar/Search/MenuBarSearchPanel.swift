//
//  MenuBarSearchPanel.swift
//  Ice
//

import Combine
import Ifrit
import SwiftUI

/// A panel that contains the menu bar search interface.
final class MenuBarSearchPanel: NSPanel {
    /// The default screen to show the panel on.
    static var defaultScreen: NSScreen? {
        NSScreen.screenWithMouse ?? NSScreen.main
    }

    /// The shared app state.
    private weak var appState: AppState?

    /// Storage for internal observers.
    private var cancellables = Set<AnyCancellable>()

    /// Model for menu bar item search.
    private let model = MenuBarSearchModel()

    /// Monitor for mouse down events.
    private lazy var mouseDownMonitor = EventMonitor.universal(
        for: [.leftMouseDown, .rightMouseDown, .otherMouseDown]
    ) { [weak self, weak appState] event in
        guard
            let self,
            let appState,
            event.window !== self
        else {
            return event
        }
        if !appState.itemManager.latestMoveOperationStarted(within: .seconds(1)) {
            close()
        }
        return event
    }

    /// Monitor for key down events.
    private lazy var keyDownMonitor = EventMonitor.universal(
        for: [.keyDown]
    ) { [weak self] event in
        if KeyCode(rawValue: Int(event.keyCode)) == .escape {
            self?.close()
            return nil
        }
        return event
    }

    /// Overridden to always be `true`.
    override var canBecomeKey: Bool { true }

    /// Creates a menu bar search panel.
    init() {
        super.init(
            contentRect: .zero,
            styleMask: [.titled, .fullSizeContentView, .nonactivatingPanel, .utilityWindow, .hudWindow],
            backing: .buffered,
            defer: false
        )
        self.titlebarAppearsTransparent = true
        self.isMovableByWindowBackground = false
        self.animationBehavior = .none
        self.isFloatingPanel = true
        self.level = .floating
        self.collectionBehavior = [.fullScreenAuxiliary, .ignoresCycle, .moveToActiveSpace]
    }

    /// Performs the initial setup of the panel.
    func performSetup(with appState: AppState) {
        self.appState = appState
        configureCancellables()
        model.performSetup(with: self)
    }

    /// Configures the internal observers for the panel.
    private func configureCancellables() {
        var c = Set<AnyCancellable>()

        NSApp.publisher(for: \.effectiveAppearance)
            .sink { [weak self] effectiveAppearance in
                self?.appearance = effectiveAppearance
            }
            .store(in: &c)

        // Close the panel when the active space changes, or when the screen parameters change.
        Publishers.Merge(
            NSWorkspace.shared.notificationCenter.publisher(for: NSWorkspace.activeSpaceDidChangeNotification),
            NotificationCenter.default.publisher(for: NSApplication.didChangeScreenParametersNotification)
        )
        .sink { [weak self] _ in
            self?.close()
        }
        .store(in: &c)

        cancellables = c
    }

    /// Shows the search panel on the given screen.
    func show(on screen: NSScreen) {
        guard let appState else {
            return
        }

        // Important that we set the navigation state before updating the cache.
        appState.navigationState.isSearchPresented = true

        Task {
            await appState.imageCache.updateCache()

            let hostingView = MenuBarSearchHostingView(appState: appState, model: model, displayID: screen.displayID, panel: self)
            hostingView.setFrameSize(hostingView.intrinsicContentSize)
            setFrame(hostingView.frame, display: true)

            contentView = hostingView

            // Calculate the top left position.
            let topLeft = CGPoint(
                x: screen.frame.midX - frame.width / 2,
                y: screen.frame.midY + (frame.height / 2) + (screen.frame.height / 8)
            )

            cascadeTopLeft(from: topLeft)
            makeKeyAndOrderFront(nil)

            mouseDownMonitor.start()
            keyDownMonitor.start()
        }
    }

    /// Toggles the panel's visibility.
    func toggle() {
        if isVisible {
            close()
        } else if let screen = MenuBarSearchPanel.defaultScreen {
            show(on: screen)
        }
    }

    /// Dismisses the search panel.
    override func close() {
        super.close()
        contentView = nil
        mouseDownMonitor.stop()
        keyDownMonitor.stop()
        appState?.navigationState.isSearchPresented = false
    }
}

private final class MenuBarSearchHostingView: NSHostingView<AnyView> {
    override var safeAreaInsets: NSEdgeInsets {
        NSEdgeInsets()
    }

    init(
        appState: AppState,
        model: MenuBarSearchModel,
        displayID: CGDirectDisplayID,
        panel: MenuBarSearchPanel
    ) {
        super.init(
            rootView: MenuBarSearchContentView(
                displayID: displayID,
                closePanel: { [weak panel] in panel?.close() }
            )
            .environmentObject(appState)
            .environmentObject(appState.itemManager)
            .environmentObject(appState.imageCache)
            .environmentObject(model)
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
}

private struct MenuBarSearchContentView: View {
    private typealias ListItem = SectionedListItem<MenuBarSearchModel.ItemID>

    @EnvironmentObject var itemManager: MenuBarItemManager
    @EnvironmentObject var model: MenuBarSearchModel
    @FocusState private var searchFieldIsFocused: Bool

    let displayID: CGDirectDisplayID
    let closePanel: () -> Void

    private var bottomBarPadding: CGFloat {
        if #available(macOS 26.0, *) {
            return 7
        } else {
            return 5
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            TextField(text: $model.searchText, prompt: Text("Search menu bar items…")) {
                Text("Search menu bar items…")
            }
            .labelsHidden()
            .textFieldStyle(.plain)
            .multilineTextAlignment(.leading)
            .font(.system(size: 18))
            .padding(15)
            .focused($searchFieldIsFocused)

            Divider()

            if itemManager.itemCache.managedItems.isEmpty {
                VStack {
                    Text("Loading menu bar items…")
                        .font(.title2)
                    ProgressView()
                        .controlSize(.small)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if #available(macOS 26.0, *) {
                GlassEffectContainer(spacing: 0) {
                    SectionedList(selection: $model.selection, items: $model.displayedItems)
                        .contentPadding(8)
                        .scrollContentBackground(.hidden)
                }
                .clipped()
            } else {
                SectionedList(selection: $model.selection, items: $model.displayedItems)
                    .contentPadding(8)
                    .scrollContentBackground(.hidden)
            }

            Divider()
                .offset(y: 1)
                .zIndex(1)

            HStack {
                SettingsButton {
                    closePanel()
                    itemManager.appState?.activate(withPolicy: .regular)
                    itemManager.appState?.openWindow(.settings)
                }

                Spacer()

                if
                    let selection = model.selection,
                    let item = menuBarItem(for: selection)
                {
                    ShowItemButton(item: item, displayID: displayID) {
                        performAction(for: item)
                    }
                }
            }
            .padding(bottomBarPadding)
            .background(.thinMaterial)
        }
        .background {
            VisualEffectView(material: .sheet, blendingMode: .behindWindow)
                .opacity(0.5)
        }
        .frame(width: 600, height: 400)
        .fixedSize()
        .task {
            searchFieldIsFocused = true
        }
        .onChange(of: model.searchText, initial: true) {
            updateDisplayedItems()
            selectFirstDisplayedItem()
        }
        .onChange(of: itemManager.itemCache, initial: true) {
            updateDisplayedItems()
            if model.selection == nil {
                selectFirstDisplayedItem()
            }
        }
    }

    private func selectFirstDisplayedItem() {
        model.selection = model.displayedItems.first { $0.isSelectable }?.id
    }

    private func updateDisplayedItems() {
        let searchItems: [(listItem: ListItem, title: String)] = MenuBarSection.Name.allCases.reduce(into: []) { items, section in
            if itemManager.appState?.menuBarManager.section(withName: section)?.isEnabled == false {
                return
            }

            let headerItem = ListItem.header(id: .header(section)) {
                Text(section.displayString)
                    .fontWeight(.semibold)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.vertical, 10)
            }
            items.append((headerItem, section.displayString))

            for item in itemManager.itemCache.managedItems(for: section).reversed() {
                let listItem = ListItem.item(id: .item(item.tag)) {
                    performAction(for: item)
                } content: {
                    MenuBarSearchItemView(item: item)
                }
                items.append((listItem, item.displayName))
            }
        }

        let searchText = model.searchText

        if searchText.isEmpty {
            model.displayedItems = searchItems.map { $0.listItem }
        } else {
            let selectableItems = searchItems.compactMap { searchItem in
                if searchItem.listItem.isSelectable {
                    return searchItem
                }
                return nil
            }

            let fuseResults = model.fuse.searchSync(searchText, in: selectableItems.map { $0.title })
            let maxFuseScore = Double(fuseResults.count)

            let scoredItems: [(listItem: ListItem, score: Double)] = fuseResults.enumerated().map { index, result in
                let searchItem = selectableItems[result.index]
                let fuseScore = maxFuseScore - Double(index)

                guard let match = bestMatch(query: searchText, input: searchItem.title, boundaryBonus: 16, camelCaseBonus: 16) else {
                    return (searchItem.listItem, fuseScore)
                }

                let matchScore = Double(match.score.value)
                let averageScore = (matchScore + fuseScore) / 2

                return (searchItem.listItem, averageScore)
            }

            model.displayedItems = scoredItems.lazy.sorted { $0.score > $1.score }.map { $0.listItem }
        }
    }

    private func menuBarItem(for selection: MenuBarSearchModel.ItemID) -> MenuBarItem? {
        switch selection {
        case .item(let tag): itemManager.itemCache.managedItems.first(matching: tag)
        case .header: nil
        }
    }

    private func performAction(for item: MenuBarItem) {
        closePanel()
        Task {
            try await Task.sleep(for: .milliseconds(25))
            if Bridging.isWindowOnDisplay(item.windowID, displayID) {
                try await itemManager.click(item: item, with: .left)
            } else {
                await itemManager.tempShow(item: item, clickingWith: .left)
            }
        }
    }
}

private struct BottomBarButton<Content: View>: View {
    @State private var frame = CGRect.zero
    @State private var isHovering = false
    @State private var isPressed = false

    let content: Content
    let action: () -> Void

    private var backgroundShape: some InsettableShape {
        if #available(macOS 26.0, *) {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
        } else {
            RoundedRectangle(cornerRadius: 5, style: .circular)
        }
    }

    init(action: @escaping () -> Void, @ViewBuilder content: () -> Content) {
        self.action = action
        self.content = content()
    }

    var body: some View {
        content
            .padding(3)
            .background {
                backgroundShape
                    .fill(.regularMaterial)
                    .brightness(0.25)
                    .opacity(isPressed ? 0.5 : isHovering ? 0.25 : 0)
            }
            .contentShape(Rectangle())
            .onHover { hovering in
                isHovering = hovering
            }
            .simultaneousGesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { value in
                        isPressed = frame.contains(value.location)
                    }
                    .onEnded { value in
                        isPressed = false
                        if frame.contains(value.location) {
                            action()
                        }
                    }
            )
            .onFrameChange(update: $frame)
    }
}

private struct SettingsButton: View {
    let action: () -> Void

    var body: some View {
        BottomBarButton(action: action) {
            Image(.iceCubeStroke)
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(width: 18, height: 18)
                .foregroundStyle(.secondary)
                .padding(2)
        }
    }
}

private struct ShowItemButton: View {
    let item: MenuBarItem
    let displayID: CGDirectDisplayID
    let action: () -> Void

    private var backgroundShape: some InsettableShape {
        if #available(macOS 26.0, *) {
            RoundedRectangle(cornerRadius: 5, style: .continuous)
        } else {
            RoundedRectangle(cornerRadius: 3, style: .circular)
        }
    }

    private var isOnDisplay: Bool {
        Bridging.isWindowOnDisplay(item.windowID, displayID)
    }

    var body: some View {
        BottomBarButton(action: action) {
            HStack {
                Text("\(isOnDisplay ? "Click" : "Show") item")
                    .padding(.leading, 5)

                Image(systemName: "return")
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(width: 11, height: 11)
                    .foregroundStyle(.secondary)
                    .fontWeight(.bold)
                    .padding(.horizontal, 7)
                    .padding(.vertical, 5)
                    .background {
                        backgroundShape
                            .fill(.regularMaterial)
                            .brightness(0.25)
                            .opacity(0.5)
                    }
            }
        }
    }
}

@MainActor
private let controlCenterIcon: NSImage? = {
    guard let app = NSRunningApplication.runningApplications(withBundleIdentifier: "com.apple.controlcenter").first else {
        return nil
    }
    return app.icon
}()

private struct MenuBarSearchItemView: View {
    @EnvironmentObject var appState: AppState
    @EnvironmentObject var imageCache: MenuBarItemImageCache
    @EnvironmentObject var model: MenuBarSearchModel

    let item: MenuBarItem

    private var image: NSImage {
        guard
            let cachedImage = imageCache.images[item.tag],
            let trimmedImage = cachedImage.cgImage.trimmingTransparentPixels(around: [.minXEdge, .maxXEdge])
        else {
            return NSImage()
        }
        let size = CGSize(
            width: CGFloat(trimmedImage.width) / cachedImage.scale,
            height: CGFloat(trimmedImage.height) / cachedImage.scale
        )
        return NSImage(cgImage: trimmedImage, size: size)
    }

    private var appIcon: NSImage? {
        guard let sourceApplication = item.sourceApplication else {
            return nil
        }
        switch item.tag.namespace {
        case .controlCenter, .systemUIServer, .textInputMenuAgent:
            return controlCenterIcon
        default:
            return sourceApplication.icon
        }
    }

    private var backgroundShape: some InsettableShape {
        if #available(macOS 26.0, *) {
            RoundedRectangle(cornerRadius: 7, style: .continuous)
        } else {
            RoundedRectangle(cornerRadius: 5, style: .circular)
        }
    }

    private var size: CGFloat {
        if #available(macOS 26.0, *) {
            return 26
        } else {
            return 24
        }
    }

    private var padding: CGFloat {
        if #available(macOS 26.0, *) {
            return 6
        } else {
            return 8
        }
    }

    var body: some View {
        HStack {
            iconViewWithFrame
            Text(item.displayName)
            Spacer()
            imageViewWithBackground
        }
        .padding(padding)
    }

    @ViewBuilder
    private var iconViewWithFrame: some View {
        iconView
            .frame(width: size, height: size)
    }

    @ViewBuilder
    private var iconView: some View {
        if let appIcon {
            Image(nsImage: appIcon)
                .resizable()
                .aspectRatio(contentMode: .fit)
        } else {
            RoundedRectangle(cornerRadius: 5)
                .fill(Color.accentColor.gradient)
                .strokeBorder(Color.primary.gradient.quaternary)
                .overlay {
                    Image(systemName: "rectangle.topthird.inset.filled")
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .foregroundStyle(.white)
                        .padding(3)
                        .shadow(radius: 2)
                }
                .padding(2.5)
                .shadow(color: .black.opacity(0.1), radius: 2)
        }
    }

    @ViewBuilder
    private var imageViewWithBackground: some View {
        imageView
            .menuBarItemContainer(appState: appState, colorInfo: model.averageColorInfo)
            .clipShape(backgroundShape)
            .overlay {
                backgroundShape
                    .strokeBorder(.quaternary)
            }
    }

    @ViewBuilder
    private var imageView: some View {
        Image(nsImage: image)
            .frame(width: item.bounds.width, height: size)
    }
}
