//
//  MenuBarSearchPanel.swift
//  Ice
//

import SwiftUI

class MenuBarSearchPanel: NSPanel {
    private weak var appState: AppState?

    init(appState: AppState) {
        super.init(
            contentRect: .zero,
            styleMask: [.titled, .fullSizeContentView, .nonactivatingPanel, .hudWindow],
            backing: .buffered,
            defer: false
        )
        self.appState = appState
        self.titlebarAppearsTransparent = true
        self.animationBehavior = .none
        self.level = .floating
    }

    func show(on screen: NSScreen) async {
        guard let appState else {
            return
        }

        // important that we set the navigation before updating the cache
        appState.navigationState.isSearchPresented = true

        await appState.imageCache.updateCache()

        self.contentView = MenuBarSearchHostingView(appState: appState, closePanel: { [weak self] in
            self?.close()
        })

        center()
        orderFrontRegardless()
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
    @EnvironmentObject var appState: AppState
    @EnvironmentObject var itemManager: MenuBarItemManager
    @EnvironmentObject var imageCache: MenuBarItemImageCache
    @State private var searchText = ""
    @State private var selection: MenuBarItem?

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
            .padding(10)

            Divider()

            scrollView
        }
        .background(.background.opacity(0.75))
        .frame(minWidth: 400)
        .frame(height: 300)
        .fixedSize()
    }

    @ViewBuilder
    private var scrollView: some View {
        ScrollView {
            VStack {
                ForEach(MenuBarSection.Name.allCases, id: \.self) { section in
                    Text(section.menuString)
                        .bold()
                        .foregroundStyle(.secondary)
                        .padding(.horizontal)
                        .padding(.vertical, 5)
                        .frame(maxWidth: .infinity, alignment: .leading)

                    VStack(spacing: 0) {
                        ForEach(itemManager.itemCache.managedItems(for: section).reversed(), id: \.info) { item in
                            MenuBarSearchItemView(item: item, closePanel: closePanel).tag(item)
                        }
                    }
                }
            }
        }
        .scrollContentBackground(.hidden)
    }
}

private struct MenuBarSearchItemView: View {
    @EnvironmentObject var imageCache: MenuBarItemImageCache

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

    var body: some View {
        HStack {
            Text(item.displayName)
            Spacer()
            if let image {
                Image(nsImage: image)
                    .contentShape(Rectangle())
            }
        }
        .padding(.horizontal)
        .padding(.vertical, 3)
    }
}
