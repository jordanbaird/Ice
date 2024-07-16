//
//  MenuBarSearchPanel.swift
//  Ice
//

import Combine
import SwiftUI

class MenuBarSearchPanel: NSPanel {
    private weak var appState: AppState?

    private var mouseDownMonitor: GlobalEventMonitor?

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

        mouseDownMonitor = GlobalEventMonitor(mask: [.leftMouseDown, .rightMouseDown]) { [weak self] _ in
            self?.close()
        }
        mouseDownMonitor?.start()

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
        mouseDownMonitor = nil
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
    @State private var searchText = ""
    @State private var selection: MenuBarItem?
    @FocusState private var searchFieldIsFocused: Bool

    let closePanel: () -> Void

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
            selection = itemManager.itemCache.managedItems(for: .visible).last
            searchFieldIsFocused = true
        }
    }

    @ViewBuilder
    private var scrollView: some View {
        ScrollView {
            VStack(spacing: 0) {
                ForEach(MenuBarSection.Name.allCases, id: \.self) { section in
                    Text(section.menuString)
                        .fontWeight(.semibold)
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.vertical, 10)

                    VStack(spacing: 0) {
                        ForEach(itemManager.itemCache.managedItems(for: section).reversed(), id: \.info) { item in
                            MenuBarSearchItemView(selection: $selection, item: item, closePanel: closePanel).tag(item)
                        }
                    }
                }
            }
            .padding([.bottom, .horizontal], 10)
        }
        .scrollContentBackground(.hidden)
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
    @Binding var selection: MenuBarItem?
    @State private var isHovering = false

    let item: MenuBarItem
    let closePanel: () -> Void

    private var image: NSImage? {
        guard
            let image = imageCache.images[item.info]?.trimmingTransparentPixels(),
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

    private var itemBackgroundStyle: AnyShapeStyle {
        if selection?.info == item.info {
            AnyShapeStyle(.selection)
        } else if isHovering {
            AnyShapeStyle(.selection.opacity(0.5))
        } else {
            AnyShapeStyle(.clear)
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
            selection = item
        }
    }

    @ViewBuilder
    private var itemBackground: some View {
        RoundedRectangle(cornerRadius: 7, style: .circular)
            .fill(itemBackgroundStyle)
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
        .padding(5)
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
