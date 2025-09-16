//
//  MenuBarSearchPanel.swift
//  Ice
//

import Combine
import Ifrit
import OSLog
import SwiftUI

/// A panel that contains the menu bar search interface.
final class MenuBarSearchPanel: NSPanel {
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
        if !appState.itemManager.lastMoveOperationOccurred(within: .seconds(1)) {
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

    /// The default screen to show the panel on.
    var defaultScreen: NSScreen? {
        NSScreen.screenWithMouse ?? NSScreen.main
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
    func show(on screen: NSScreen? = nil) {
        guard let appState else {
            return
        }

        guard let screen = screen ?? defaultScreen else {
            Logger.default.error("Missing screen for search panel")
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
        if isVisible { close() } else { show() }
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
            rootView: MenuBarSearchContentView { [weak panel] in panel?.close() }
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

    let closePanel: () -> Void

    private var hasItems: Bool {
        !itemManager.itemCache.managedItems.isEmpty
    }

    private var bottomBarPadding: CGFloat {
        if #available(macOS 26.0, *) { 7 } else { 5 }
    }

    var body: some View {
        VStack(spacing: 0) {
            searchField
            mainContent
            bottomBar
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

    @ViewBuilder
    private var searchField: some View {
        let promptText = Text("Search menu bar items…")

        VStack(spacing: 0) {
            TextField(text: $model.searchText, prompt: promptText) {
                promptText
            }
            .labelsHidden()
            .textFieldStyle(.plain)
            .multilineTextAlignment(.leading)
            .font(.system(size: 18))
            .padding(15)
            .focused($searchFieldIsFocused)

            Divider()
        }
    }

    @ViewBuilder
    private var mainContent: some View {
        if hasItems {
            SectionedList(selection: $model.selection, items: $model.displayedItems)
                .contentPadding(8)
                .scrollContentBackground(.hidden)
        } else {
            VStack {
                Text("Loading menu bar items…")
                    .font(.title2)
                ProgressView()
                    .controlSize(.small)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    @ViewBuilder
    private var bottomBar: some View {
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
                ShowItemButton(item: item) {
                    performAction(for: item)
                }
            }
        }
        .padding(bottomBarPadding)
        .background(.thinMaterial)
        .buttonStyle(BottomBarButtonStyle())
        .overlay(alignment: .top) {
            Divider()
        }
    }

    private func selectFirstDisplayedItem() {
        model.selection = model.displayedItems.first { $0.isSelectable }?.id
    }

    private func updateDisplayedItems() {
        typealias SearchItem = (listItem: ListItem, title: String)
        typealias ScoredItem = (listItem: ListItem, score: Double)

        let searchItems: [SearchItem] = MenuBarSection.Name.allCases
            .reduce(into: []) { items, name in
                if
                    let appState = itemManager.appState,
                    let section = appState.menuBarManager.section(withName: name),
                    !section.isEnabled
                {
                    return
                }

                let headerItem = ListItem.header(id: .header(name)) {
                    Text(name.displayString)
                        .fontWeight(.semibold)
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.vertical, 10)
                }
                items.append(SearchItem(headerItem, name.displayString))

                for item in itemManager.itemCache.managedItems(for: name).reversed() {
                    let listItem = ListItem.item(id: .item(item.tag)) {
                        performAction(for: item)
                    } content: {
                        MenuBarSearchItemView(item: item)
                    }
                    items.append(SearchItem(listItem, item.displayName))
                }
            }

        if model.searchText.isEmpty {
            model.displayedItems = searchItems.map { $0.listItem }
        } else {
            let selectableItems = searchItems.filter { $0.listItem.isSelectable }
            let fuseResults = model.fuse.searchSync(
                model.searchText,
                in: selectableItems.map { $0.title }
            )
            let maxFuseScore = Double(fuseResults.count)

            model.displayedItems = fuseResults.enumerated()
                .map { index, result in
                    let fuseScore = maxFuseScore - Double(index)
                    let (listItem, title) = selectableItems[result.index]

                    guard let match = bestMatch(
                        query: model.searchText,
                        input: title,
                        boundaryBonus: 16,
                        camelCaseBonus: 16
                    ) else {
                        return ScoredItem(listItem, fuseScore)
                    }

                    let matchScore = Double(match.score.value)
                    let averageScore = (matchScore + fuseScore) / 2

                    return ScoredItem(listItem, averageScore)
                }
                .sorted { $0.score > $1.score }
                .map { $0.listItem }
        }
    }

    private func menuBarItem(for selection: MenuBarSearchModel.ItemID) -> MenuBarItem? {
        switch selection {
        case .item(let tag):
            return itemManager.itemCache.managedItems.first(matching: tag)
        case .header:
            return nil
        }
    }

    private func performAction(for item: MenuBarItem) {
        closePanel()
        Task {
            try await Task.sleep(for: .milliseconds(25))
            if Bridging.isWindowOnScreen(item.windowID) {
                try await itemManager.click(item: item, with: .left)
            } else {
                await itemManager.temporarilyShow(item: item, clickingWith: .left)
            }
        }
    }
}

private struct SettingsButton: View {
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(.iceCubeStroke)
                .resizable()
                .aspectRatio(contentMode: .fit)
                .foregroundStyle(.secondary)
                .padding(2)
        }
    }
}

private struct ShowItemButton: View {
    let item: MenuBarItem
    let action: () -> Void

    private var backgroundShape: some InsettableShape {
        if #available(macOS 26.0, *) {
            RoundedRectangle(cornerRadius: 5, style: .continuous)
        } else {
            RoundedRectangle(cornerRadius: 3, style: .circular)
        }
    }

    var body: some View {
        Button(action: action) {
            HStack {
                Text("\(Bridging.isWindowOnScreen(item.windowID) ? "Click" : "Show") Item")
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

private struct BottomBarButtonStyle: ButtonStyle {
    @State private var isHovering = false

    private var borderShape: some InsettableShape {
        if #available(macOS 26.0, *) {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
        } else {
            RoundedRectangle(cornerRadius: 5, style: .circular)
        }
    }

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .frame(height: 22)
            .frame(minWidth: 22)
            .padding(3)
            .background {
                borderShape
                    .fill(.regularMaterial)
                    .brightness(0.25)
                    .opacity(configuration.isPressed ? 0.5 : isHovering ? 0.25 : 0)
            }
            .contentShape([.focusEffect, .interaction], borderShape)
            .onHover { hovering in
                isHovering = hovering
            }
    }
}

@MainActor
private let controlCenterIcon: NSImage? = {
    guard let app = NSRunningApplication
        .runningApplications(withBundleIdentifier: "com.apple.controlcenter")
        .first
    else {
        return nil
    }
    return app.icon
}()

private struct MenuBarSearchItemView: View {
    @EnvironmentObject var appState: AppState
    @EnvironmentObject var imageCache: MenuBarItemImageCache
    @EnvironmentObject var model: MenuBarSearchModel

    let item: MenuBarItem

    private var itemImage: NSImage {
        guard
            let cached = imageCache.images[item.tag],
            let trimmed = cached.cgImage.trimmingTransparency(around: [.minXEdge, .maxXEdge])
        else {
            return NSImage()
        }
        let size = CGSize(
            width: CGFloat(trimmed.width) / cached.scale,
            height: CGFloat(trimmed.height) / cached.scale
        )
        return NSImage(cgImage: trimmed, size: size)
    }

    private var appIcon: NSImage? {
        guard let app = item.sourceApplication else {
            return nil
        }
        switch item.tag.namespace {
        case .controlCenter, .systemUIServer, .textInputMenuAgent:
            return controlCenterIcon
        default:
            return app.icon
        }
    }

    private var backgroundShape: some InsettableShape {
        if #available(macOS 26.0, *) {
            RoundedRectangle(cornerRadius: 7, style: .continuous)
        } else {
            RoundedRectangle(cornerRadius: 5, style: .circular)
        }
    }

    private var dimension: CGFloat {
        if #available(macOS 26.0, *) { 26 } else { 24 }
    }

    private var padding: CGFloat {
        if #available(macOS 26.0, *) { 6 } else { 8 }
    }

    var body: some View {
        HStack {
            Label {
                labelText
            } icon: {
                labelIcon
            }
            Spacer()
            itemView
        }
        .padding(padding)
    }

    @ViewBuilder
    private var labelText: some View {
        Text(item.displayName)
    }

    @ViewBuilder
    private var labelIcon: some View {
        if let appIcon {
            Image(nsImage: appIcon)
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(width: dimension, height: dimension)
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
                .frame(width: dimension, height: dimension)
        }
    }

    @ViewBuilder
    private var itemView: some View {
        Image(nsImage: itemImage)
            .frame(
                width: item.bounds.width,
                height: dimension
            )
            .menuBarItemContainer(
                appState: appState,
                colorInfo: model.averageColorInfo
            )
            .clipShape(backgroundShape)
            .overlay {
                backgroundShape
                    .strokeBorder(.quaternary)
            }
    }
}
