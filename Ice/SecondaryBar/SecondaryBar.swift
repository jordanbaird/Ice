//
//  SecondaryBar.swift
//  Ice
//

import Bridging
import Combine
import SwiftUI

// MARK: - SecondaryBarPanel

class SecondaryBarPanel: NSPanel {
    private weak var appState: AppState?

    private var imageCache = SecondaryBarImageCache()

    private(set) var currentSection: MenuBarSection.Name?

    private var cancellables = Set<AnyCancellable>()

    init(appState: AppState) {
        super.init(
            contentRect: .zero,
            styleMask: [
                .nonactivatingPanel,
                .titled,
                .fullSizeContentView,
                .hudWindow,
            ],
            backing: .buffered,
            defer: false
        )
        self.appState = appState
        self.titlebarAppearsTransparent = true
        self.isMovableByWindowBackground = true
        self.animationBehavior = .none
        self.level = .mainMenu
        self.collectionBehavior = [.fullScreenNone, .ignoresCycle, .moveToActiveSpace]
        configureCancellables()
    }

    private func configureCancellables() {
        var c = Set<AnyCancellable>()

        // close the panel when the active space changes
        NSWorkspace.shared.notificationCenter
            .publisher(for: NSWorkspace.activeSpaceDidChangeNotification)
            .debounce(for: 0.1, scheduler: DispatchQueue.main)
            .sink { [weak self] _ in
                guard let self else {
                    return
                }
                close()
                imageCache.clear()
            }
            .store(in: &c)

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
        let origin = CGPoint(
            x: (screen.visibleFrame.maxX - frame.width) - 5,
            y: (screen.visibleFrame.maxY - frame.height) - 5
        )
        setFrameOrigin(origin)
    }

    func show(section: MenuBarSection.Name, on screen: NSScreen) {
        guard let appState else {
            return
        }
        contentView = SecondaryBarHostingView(
            appState: appState,
            imageCache: imageCache,
            section: section
        ) { [weak self] in
            self?.close()
        }
        updateOrigin(for: screen)
        makeKeyAndOrderFront(nil)
        currentSection = section
    }

    override func close() {
        super.close()
        contentView = nil
        currentSection = nil
    }
}

// MARK: - SecondaryBarImageCache

private class SecondaryBarImageCache: ObservableObject {
    @Published private var images = [MenuBarItemInfo: CGImage]()

    func image(for info: MenuBarItemInfo) -> CGImage? {
        images[info]
    }

    func cache(image: CGImage, for info: MenuBarItemInfo) {
        DispatchQueue.main.async {
            self.images[info] = image
        }
    }

    func clear() {
        DispatchQueue.main.async {
            self.images.removeAll()
        }
    }
}

// MARK: - SecondaryBarHostingView

private class SecondaryBarHostingView: NSHostingView<AnyView> {
    override var safeAreaInsets: NSEdgeInsets {
        NSEdgeInsets()
    }

    init(
        appState: AppState,
        imageCache: SecondaryBarImageCache,
        section: MenuBarSection.Name,
        closePanel: @escaping () -> Void
    ) {
        super.init(
            rootView: SecondaryBarContentView(section: section, closePanel: closePanel)
                .environmentObject(appState.itemManager)
                .environmentObject(appState.menuBarManager)
                .environmentObject(imageCache)
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

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool {
        return true
    }
}

// MARK: - SecondaryBarContentView

private struct SecondaryBarContentView: View {
    @EnvironmentObject var itemManager: MenuBarItemManager
    @EnvironmentObject var menuBarManager: MenuBarManager

    let section: MenuBarSection.Name
    let closePanel: () -> Void

    private var items: [MenuBarItem] {
        itemManager.cachedMenuBarItems[section, default: []]
    }

    var body: some View {
        HStack(spacing: 0) {
            ForEach(items, id: \.windowID) { item in
                SecondaryBarItemView(item: item, closePanel: closePanel)
            }
        }
        .padding(5)
        .layoutBarStyle(menuBarManager: menuBarManager, cornerRadius: 0)
        .fixedSize()
    }
}

// MARK: - SecondaryBarItemView

private struct SecondaryBarItemView: View {
    @EnvironmentObject var itemManager: MenuBarItemManager
    @EnvironmentObject var imageCache: SecondaryBarImageCache

    let item: MenuBarItem
    let closePanel: () -> Void

    private var image: CGImage? {
        let info = item.info
        if let image = imageCache.image(for: info) {
            return image
        }
        if let image = Bridging.captureWindow(item.windowID, option: .boundsIgnoreFraming) {
            imageCache.cache(image: image, for: info)
            return image
        }
        return nil
    }

    private var size: CGSize? {
        let frame = Bridging.getWindowFrame(for: item.windowID)
        return frame?.size
    }

    var body: some View {
        if let image, let size {
            Image(nsImage: NSImage(cgImage: image, size: size))
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(
                    width: size.width,
                    height: size.height
                )
                .onTapGesture {
                    closePanel()
                    itemManager.temporarilyShowItem(item)
                }
        }
    }
}
