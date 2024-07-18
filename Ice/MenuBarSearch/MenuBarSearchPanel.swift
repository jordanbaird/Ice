//
//  MenuBarSearchPanel.swift
//  Ice
//

import Combine
import Ifrit
import SwiftUI

class MenuBarSearchPanel: NSPanel {
    private weak var appState: AppState?

    private var mouseDownMonitor: UniversalEventMonitor?

    private var keyDownMonitor: UniversalEventMonitor?

    private var cancellables = Set<AnyCancellable>()

    override var canBecomeKey: Bool { true }

    init(appState: AppState) {
        super.init(
            contentRect: .zero,
            styleMask: [.titled, .fullSizeContentView, .nonactivatingPanel, .hudWindow],
            backing: .buffered,
            defer: false
        )
        self.appState = appState
        self.titlebarAppearsTransparent = true
        self.isMovableByWindowBackground = false
        self.animationBehavior = .none
        self.level = .floating
        configureCancellables()
    }

    private func configureCancellables() {
        var c = Set<AnyCancellable>()

        NSApp.publisher(for: \.effectiveAppearance)
            .sink { [weak self] effectiveAppearance in
                self?.appearance = effectiveAppearance
            }
            .store(in: &c)

        cancellables = c
    }

    func show(on screen: NSScreen) async {
        guard let appState else {
            return
        }

        // important that we set the navigation before updating the cache
        appState.navigationState.isSearchPresented = true

        await appState.imageCache.updateCache()

        contentView = MenuBarSearchHostingView(appState: appState, closePanel: { [weak self] in
            self?.close()
        })

        mouseDownMonitor = UniversalEventMonitor(mask: [.leftMouseDown, .rightMouseDown, .otherMouseDown]) { [weak self] event in
            guard
                let self,
                event.window !== self
            else {
                return event
            }
            close()
            return event
        }
        keyDownMonitor = UniversalEventMonitor(mask: .keyDown) { [weak self] event in
            if KeyCode(rawValue: Int(event.keyCode)) == .escape {
                self?.close()
                return nil
            }
            return event
        }

        mouseDownMonitor?.start()
        keyDownMonitor?.start()

        let topLeft = CGPoint(
            x: screen.frame.midX - frame.width / 2,
            y: screen.frame.midY + (frame.height / 2) + (screen.frame.height / 8)
        )

        cascadeTopLeft(from: topLeft)
        makeKeyAndOrderFront(nil)
    }

    func toggle() async {
        if isVisible {
            close()
        } else if let screen = NSScreen.screenWithMouse ?? NSScreen.main {
            await show(on: screen)
        }
    }

    override func close() {
        super.close()
        contentView = nil
        mouseDownMonitor?.stop()
        keyDownMonitor?.stop()
        mouseDownMonitor = nil
        keyDownMonitor = nil
        appState?.navigationState.isSearchPresented = false
    }
}

private class MenuBarSearchHostingView: NSHostingView<AnyView> {
    override var safeAreaInsets: NSEdgeInsets {
        NSEdgeInsets()
    }

    init(
        appState: AppState,
        closePanel: @escaping () -> Void
    ) {
        super.init(
            rootView: MenuBarSearchContentView(closePanel: closePanel)
                .environmentObject(appState)
                .environmentObject(appState.itemManager)
                .environmentObject(appState.imageCache)
                .environmentObject(appState.menuBarManager)
                .erased()
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
    @EnvironmentObject var itemManager: MenuBarItemManager

    let closePanel: () -> Void

    var body: some View {
        MenuBarSearchEquatableContentView(
            itemCache: itemManager.itemCache,
            closePanel: closePanel
        )
        .equatable()
    }
}

private struct MenuBarSearchSelectionValue: Hashable {
    var sectionIndex: Int
    var itemIndex: Int
}

private struct MenuBarSearchEquatableContentView: View, Equatable {
    @State private var searchText = ""
    @State private var selection = MenuBarSearchSelectionValue(sectionIndex: 0, itemIndex: 0)
    @State private var itemFrames = [MenuBarSearchSelectionValue: CGRect]()
    @State private var scrollContentOffset: CGFloat = 0
    @FocusState private var searchFieldIsFocused: Bool

    let itemCache: MenuBarItemManager.ItemCache
    let closePanel: () -> Void

    private let fuse = Fuse(threshold: 0.5, tokenize: false)

    private var matchingItems: [MenuBarItem] {
        let managedItems = itemCache.managedItems
        if searchText.isEmpty {
            return managedItems.reversed()
        }
        let results = fuse.searchSync(searchText, in: managedItems.map { $0.displayName })
        let indices = results.map { $0.index }
        return indices.map { managedItems[$0] }
    }

    var body: some View {
        VStack(spacing: 0) {
            TextField(text: $searchText, prompt: Text("Search menu bar items…")) {
                Text("Search menu bar items…")
            }
            .labelsHidden()
            .textFieldStyle(.plain)
            .multilineTextAlignment(.leading)
            .font(.system(size: 18))
            .padding(15)
            .focused($searchFieldIsFocused)

            Divider()

            scrollView
        }
        .background(.background.opacity(0.75))
        .frame(minWidth: 550)
        .frame(height: 365)
        .fixedSize()
        .onAppear {
            searchFieldIsFocused = true
        }
    }

    @ViewBuilder
    private var scrollView: some View {
        ScrollViewReader { scrollView in
            GeometryReader { geometry in
                ScrollView {
                    scrollContent(scrollView: scrollView, geometry: geometry)
                }
                .scrollContentBackground(.hidden)
            }
        }
    }

    @ViewBuilder
    private func scrollContent(scrollView: ScrollViewProxy, geometry: GeometryProxy) -> some View {
        VStack(spacing: 0) {
            if searchText.isEmpty {
                ForEach(Array(MenuBarSection.Name.allCases.enumerated()), id: \.element) { index, section in
                    listSection(sectionIndex: index, section: section)
                        .offset(y: scrollContentOffset)
                }
            } else {
                ForEach(Array(matchingItems.enumerated()), id: \.element) { index, item in
                    MenuBarSearchItemView(
                        selection: $selection,
                        itemFrames: $itemFrames,
                        item: item,
                        selectionValue: selectionValue(0, index),
                        closePanel: closePanel
                    )
                    .id(selectionValue(0, index))
                    .offset(y: scrollContentOffset)
                }
            }
        }
        .padding([.bottom, .horizontal], 8)
        .onKeyDown(key: .downArrow) {
            let section = MenuBarSection.Name.allCases[selection.sectionIndex]
            let items = itemCache.managedItems(for: section)
            if selection.itemIndex >= items.endIndex - 1 {
                if selection.sectionIndex < MenuBarSection.Name.allCases.endIndex - 1 {
                    selection.sectionIndex += 1
                    selection.itemIndex = 0
                }
            } else if selection.itemIndex < items.endIndex {
                selection.itemIndex += 1
            }
            if needsScrollToSelection(geometry: geometry) {
                scrollView.scrollTo(selection, anchor: .bottom)
                scrollContentOffset = -8
            }
        }
        .onKeyDown(key: .upArrow) {
            let section = MenuBarSection.Name.allCases[selection.sectionIndex]
            let items = itemCache.managedItems(for: section)
            if selection.itemIndex <= items.startIndex {
                if selection.sectionIndex > MenuBarSection.Name.allCases.startIndex {
                    let previousItems = itemCache.managedItems(for: MenuBarSection.Name.allCases[selection.sectionIndex - 1])
                    selection.sectionIndex -= 1
                    selection.itemIndex = previousItems.endIndex - 1
                }
            } else if selection.itemIndex >= items.startIndex + 1 {
                selection.itemIndex -= 1
            }
            if needsScrollToSelection(geometry: geometry) {
                scrollView.scrollTo(selection, anchor: .top)
                scrollContentOffset = 8
            }
        }
        .localEventMonitor(mask: .scrollWheel) { event in
            scrollContentOffset = 0
            return event
        }
    }

    @ViewBuilder
    private func listSection(sectionIndex: Int, section: MenuBarSection.Name) -> some View {
        Section {
            ForEach(enumeratedItems(for: section), id: \.element.info) { itemIndex, item in
                MenuBarSearchItemView(
                    selection: $selection,
                    itemFrames: $itemFrames,
                    item: item,
                    selectionValue: selectionValue(sectionIndex, itemIndex),
                    closePanel: closePanel
                )
                .id(selectionValue(sectionIndex, itemIndex))
            }
        } header: {
            Text(section.menuString)
                .fontWeight(.semibold)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.vertical, 10)
        }
    }

    private func enumeratedItems(for section: MenuBarSection.Name) -> [(offset: Int, element: MenuBarItem)] {
        Array(itemCache.managedItems(for: section).reversed().enumerated())
    }

    private func selectionValue(_ sectionIndex: Int, _ itemIndex: Int) -> MenuBarSearchSelectionValue {
        MenuBarSearchSelectionValue(sectionIndex: sectionIndex, itemIndex: itemIndex)
    }

    private func needsScrollToSelection(geometry: GeometryProxy) -> Bool {
        guard let selectionFrame = itemFrames[selection] else {
            return false
        }
        let geometryFrame = geometry.frame(in: .global)
        return !geometryFrame.contains(selectionFrame)
    }

    static func == (lhs: MenuBarSearchEquatableContentView, rhs: MenuBarSearchEquatableContentView) -> Bool {
        lhs.itemCache == rhs.itemCache
    }
}

private let controlCenterIcon: NSImage? = {
    guard let app = NSRunningApplication.runningApplications(withBundleIdentifier: "com.apple.controlcenter").first else {
        return nil
    }
    return app.icon
}()

private struct MenuBarSearchItemView: View {
    @EnvironmentObject var imageCache: MenuBarItemImageCache
    @EnvironmentObject var menuBarManager: MenuBarManager
    @Binding var selection: MenuBarSearchSelectionValue
    @Binding var itemFrames: [MenuBarSearchSelectionValue: CGRect]
    @State private var isHovering = false

    let item: MenuBarItem
    let selectionValue: MenuBarSearchSelectionValue
    let closePanel: () -> Void

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

    private var appIcon: NSImage? {
        if item.info.namespace == .systemUIServer {
            controlCenterIcon
        } else {
            item.owningApplication?.icon
        }
    }

    private var imageBackgroundColor: Color {
        if let colorInfo = menuBarManager.averageColorInfo {
            Color(cgColor: colorInfo.color)
        } else {
            Color.gray
        }
    }

    var body: some View {
        ZStack {
            itemBackground
            itemContent
        }
        .contentShape(Rectangle())
        .onHover { hovering in
            isHovering = hovering
        }
        .onTapGesture {
            selection = selectionValue
        }
        .onFrameChange(in: .global) { frame in
            itemFrames[selectionValue] = frame
        }
    }

    @ViewBuilder
    private var itemBackground: some View {
        VisualEffectView(material: .selection, blendingMode: .withinWindow)
            .clipShape(RoundedRectangle(cornerRadius: 7, style: .circular))
            .opacity(selection == selectionValue ? 0.5 : isHovering ? 0.25 : 0)
    }

    @ViewBuilder
    private var itemContent: some View {
        HStack {
            if let appIcon {
                Image(nsImage: appIcon)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(width: 24, height: 24)
            }
            Text(item.displayName)
            Spacer()
            imageViewWithBackground
        }
        .padding(8)
    }

    @ViewBuilder
    private var imageViewWithBackground: some View {
        if let image {
            ZStack {
                RoundedRectangle(cornerRadius: 5, style: .circular)
                    .fill(imageBackgroundColor)
                    .frame(width: item.frame.width)
                Image(nsImage: image)
            }
        }
    }
}
