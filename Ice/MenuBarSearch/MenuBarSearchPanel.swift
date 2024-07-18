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
            rootView: MenuBarSearchContentView(
                itemCache: appState.itemManager.itemCache,
                closePanel: closePanel
            )
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
    struct MenuBarSearchItem {
        let listItem: SectionedListItem
        let displayName: String
    }

    @State private var searchText = ""
    @State private var selection: ObjectIdentifier?
    @FocusState private var searchFieldIsFocused: Bool

    let items: [MenuBarSearchItem]
    let closePanel: () -> Void

    private let fuse = Fuse(threshold: 0.5, tokenize: false)

    private var matchingItems: [SectionedListItem] {
        if searchText.isEmpty {
            return items.map { $0.listItem }
        }
        let selectableItems = items.compactMap { item in
            if item.listItem.isSelectable {
                return item
            }
            return nil
        }
        let results = fuse.searchSync(searchText, in: selectableItems.map { $0.displayName })
        return results.map { selectableItems[$0.index].listItem }
    }

    init(itemCache: MenuBarItemManager.ItemCache, closePanel: @escaping () -> Void) {
        self.closePanel = closePanel
        self.items = MenuBarSection.Name.allCases.reduce(into: []) { items, section in
            let headerItem = SectionedListHeaderItem {
                Text(section.menuString)
                    .fontWeight(.semibold)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.vertical, 10)
            }
            items.append(MenuBarSearchItem(listItem: headerItem, displayName: section.menuString))

            for item in itemCache.managedItems(for: section).reversed() {
                let listItem = SectionedListItem(isSelectable: true, action: closePanel) {
                    MenuBarSearchItemView(item: item)
                }
                items.append(MenuBarSearchItem(listItem: listItem, displayName: item.displayName))
            }
        }
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

            SectionedList(selection: $selection, items: matchingItems) { scrollContent in
                scrollContent
                    .padding(.horizontal, 8)
            }
            .padding(.vertical, 8)
            .scrollContentBackground(.hidden)
            .scrollClipDisabled()
            .clipped()
        }
        .background(.background.opacity(0.75))
        .frame(minWidth: 550)
        .frame(height: 375)
        .fixedSize()
        .onAppear {
            searchFieldIsFocused = true
            selectFirstMatchingItem()
        }
        .onChange(of: searchText) {
            selectFirstMatchingItem()
        }
    }

    private func selectFirstMatchingItem() {
        selection = matchingItems.first { $0.isSelectable }?.id
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

    let item: MenuBarItem

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
