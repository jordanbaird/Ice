//
//  IceBar.swift
//  Ice
//

import Bridging
import Combine
import SwiftUI
import OSLog

// MARK: - IceBarPanel

class IceBarPanel: NSPanel {
    private weak var appState: AppState?

    private let imageCache: IceBarImageCache

    private var needsUpdateImageCacheBeforeShowing = true

    private let encoder = JSONEncoder()

    private let decoder = JSONDecoder()

    private(set) var currentSection: MenuBarSection.Name?

    private var cancellables = Set<AnyCancellable>()

    init(appState: AppState) {
        self.imageCache = IceBarImageCache(appState: appState)

        super.init(
            contentRect: .zero,
            styleMask: [
                .nonactivatingPanel,
                .fullSizeContentView,
                .borderless,
            ],
            backing: .buffered,
            defer: false
        )

        self.appState = appState
        self.titlebarAppearsTransparent = true
        self.isMovableByWindowBackground = true
        self.isFloatingPanel = true
        self.animationBehavior = .none
        self.backgroundColor = .clear
        self.hasShadow = true
        self.level = .mainMenu
        self.collectionBehavior = [
            .fullScreenAuxiliary,
            .ignoresCycle,
            .moveToActiveSpace,
        ]
    }

    func performSetup() {
        configureCancellables()
    }

    private func configureCancellables() {
        var c = Set<AnyCancellable>()

        Publishers.Merge(
            NSWorkspace.shared.notificationCenter.publisher(for: NSWorkspace.activeSpaceDidChangeNotification),
            NotificationCenter.default.publisher(for: NSApplication.didChangeScreenParametersNotification)
        )
        .sink { [weak self] _ in
            guard let self else {
                return
            }
            needsUpdateImageCacheBeforeShowing = true
            close()
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

        if let appState {
            appState.menuBarManager.$averageColor
                .removeDuplicates()
                .receive(on: DispatchQueue.main)
                .sink { [weak self] _ in
                    guard let self else {
                        return
                    }
                    if isVisible {
                        Task {
                            await self.imageCache.updateCache()
                        }
                    } else {
                        needsUpdateImageCacheBeforeShowing = true
                    }
                }
                .store(in: &c)
        }

        cancellables = c
    }

    private func updateOrigin(for screen: NSScreen) {
        guard
            let appState,
            let section = appState.menuBarManager.section(withName: .visible),
            let controlItemFrame = section.controlItem.windowID.flatMap(Bridging.getWindowFrame)
        else {
            return
        }
        let menuBarHeight = NSApp.mainMenu?.menuBarHeight ?? 0
        let margin: CGFloat = 5
        let origin = CGPoint(
            x: min(
                controlItemFrame.midX - frame.width / 2,
                screen.frame.maxX - frame.width - margin
            ),
            y: (screen.frame.maxY - menuBarHeight - 1) - frame.height - margin
        )
        setFrameOrigin(origin)
    }

    func show(section: MenuBarSection.Name, on screen: NSScreen) async {
        guard let appState else {
            return
        }
        if needsUpdateImageCacheBeforeShowing {
            if await imageCache.updateCache() {
                needsUpdateImageCacheBeforeShowing = false
            }
        }
        contentView = IceBarHostingView(
            appState: appState,
            imageCache: imageCache,
            section: section,
            screen: screen
        ) { [weak self] in
            self?.close()
        }
        updateOrigin(for: screen)
        orderFrontRegardless()
        currentSection = section
    }

    override func close() {
        super.close()
        contentView = nil
        currentSection = nil
    }
}

// MARK: - IceBarImageCache

@MainActor
private class IceBarImageCache: ObservableObject {
    @Published private var images = [MenuBarItemInfo: CGImage]()

    private weak var appState: AppState?

    init(appState: AppState) {
        self.appState = appState
    }

    func image(for info: MenuBarItemInfo) -> CGImage? {
        images[info]
    }

    func cacheImage(for item: MenuBarItem) async -> Bool {
        await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .userInteractive).async {
                guard
                    let image = Bridging.captureWindow(item.windowID, option: .boundsIgnoreFraming),
                    !image.isTransparent()
                else {
                    continuation.resume(returning: false)
                    return
                }
                Task.detached { @MainActor in
                    self.images[item.info] = image
                    continuation.resume(returning: true)
                }
            }
        }
    }

    func updateCache() async -> Bool {
        guard let appState else {
            return false
        }
        var results = Set<Bool>()
        for section: MenuBarSection.Name in [.hidden, .alwaysHidden] {
            guard let items = appState.itemManager.cachedMenuBarItems[section] else {
                results.insert(false)
                continue
            }
            for item in items {
                let result = await cacheImage(for: item)
                results.insert(result)
            }
        }
        return !results.contains(false)
    }
}

// MARK: - IceBarHostingView

private class IceBarHostingView: NSHostingView<AnyView> {
    override var safeAreaInsets: NSEdgeInsets {
        NSEdgeInsets()
    }

    init(
        appState: AppState,
        imageCache: IceBarImageCache,
        section: MenuBarSection.Name,
        screen: NSScreen,
        closePanel: @escaping () -> Void
    ) {
        super.init(
            rootView: IceBarContentView(section: section, screen: screen, closePanel: closePanel)
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

// MARK: - IceBarContentView

private struct IceBarContentView: View {
    @EnvironmentObject var itemManager: MenuBarItemManager
    @EnvironmentObject var menuBarManager: MenuBarManager

    let section: MenuBarSection.Name
    let screen: NSScreen
    let closePanel: () -> Void

    private var items: [MenuBarItem] {
        itemManager.cachedMenuBarItems[section, default: []]
    }

    var body: some View {
        HStack(spacing: 0) {
            ForEach(items, id: \.windowID) { item in
                IceBarItemView(item: item, screen: screen, closePanel: closePanel)
            }
        }
        .padding(5)
        .layoutBarStyle(menuBarManager: menuBarManager, cornerRadius: 0)
        .clipShape(RoundedRectangle(cornerRadius: 9))
        .overlay {
            RoundedRectangle(cornerRadius: 9)
                .inset(by: 0.5)
                .stroke(lineWidth: 0.5)
                .foregroundStyle(.tertiary)
        }
        .fixedSize()
    }
}

// MARK: - IceBarItemView

private struct IceBarItemView: View {
    @EnvironmentObject var itemManager: MenuBarItemManager
    @EnvironmentObject var imageCache: IceBarImageCache

    let item: MenuBarItem
    let screen: NSScreen
    let closePanel: () -> Void

    private var image: NSImage? {
        guard let image = imageCache.image(for: item.info) else {
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
                .onTapGesture {
                    closePanel()
                    itemManager.tempShowItem(item, clickWhenFinished: true)
                }
        }
    }
}

// MARK: - Logger

private extension Logger {
    static let iceBar = Logger(category: "IceBar")
}
