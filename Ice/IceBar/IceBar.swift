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
        self.hasShadow = false
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

        // close the panel and mark it as needing its caches updated when
        // the active space changes, or when the screen parameters change
        Publishers.Merge(
            NSWorkspace.shared.notificationCenter.publisher(for: NSWorkspace.activeSpaceDidChangeNotification),
            NotificationCenter.default.publisher(for: NSApplication.didChangeScreenParametersNotification)
        )
        .sink { [weak self] _ in
            guard let self else {
                return
            }
            close()
            needsUpdateImageCacheBeforeShowing = true
        }
        .store(in: &c)

        // update the panel's origin whenever its size changes
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
            // update image cache when the average color of the menu bar changes,
            // and when the cached menu bar items change (we map both publishers
            // to Void so we can merge them into a single publisher)
            Publishers.Merge(
                appState.menuBarManager.$averageColor.removeDuplicates().map { _ in () },
                appState.itemManager.$cachedMenuBarItems.removeDuplicates().map { _ in () }
            )
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                guard let self else {
                    return
                }
                if
                    isVisible,
                    let currentSection,
                    let screen
                {
                    Task {
                        await self.imageCache.updateCache(for: currentSection, screen: screen)
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
            // using `getWindowFrame` from Bridging is more reliable than
            // accessing the `windowFrame` property on the control item
            let controlItemFrame = section.controlItem.windowID.flatMap(Bridging.getWindowFrame)
        else {
            return
        }
        let menuBarHeight = NSApp.mainMenu?.menuBarHeight ?? 0
        let origin = CGPoint(
            x: min(
                controlItemFrame.midX - frame.width / 2,
                screen.frame.maxX - frame.width
            ),
            y: (screen.frame.maxY - menuBarHeight - 1) - frame.height
        )
        setFrameOrigin(origin)
    }

    func show(section: MenuBarSection.Name, on screen: NSScreen) async {
        guard let appState else {
            return
        }
        if needsUpdateImageCacheBeforeShowing {
            if await imageCache.updateCache(for: section, screen: screen) {
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
    @Published private(set) var images = [MenuBarItemInfo: CGImage]()

    private weak var appState: AppState?

    init(appState: AppState) {
        self.appState = appState
    }

    func isEmpty(section: MenuBarSection.Name) -> Bool {
        let keys = Set(images.keys)
        let items = appState?.itemManager.cachedMenuBarItems[section] ?? []
        for item in items where keys.contains(item.info) {
            return false
        }
        return true
    }

    func updateCache(for section: MenuBarSection.Name, screen: NSScreen) async -> Bool {
        actor TempCache {
            private(set) var images = [MenuBarItemInfo: CGImage]()

            func cache(image: CGImage, with info: MenuBarItemInfo) {
                images[info] = image
            }
        }

        guard
            let appState,
            let items = appState.itemManager.cachedMenuBarItems[section]
        else {
            return false
        }

        let tempCache = TempCache()
        let backingScaleFactor = screen.backingScaleFactor

        let cacheTask = Task.detached {
            let windowIDs = items.map { $0.windowID }

            guard
                let compositeImage = Bridging.captureWindows(windowIDs, option: .boundsIgnoreFraming),
                !compositeImage.isTransparent(maxAlpha: 0.9)
            else {
                return false
            }

            var failed = false
            var start: CGFloat = 0
            let height = CGFloat(compositeImage.height)

            for item in items {
                let width = item.frame.width * backingScaleFactor
                let frame = CGRect(x: start, y: 0, width: width, height: height)

                defer {
                    start += width
                }

                if
                    let itemImage = compositeImage.cropping(to: frame),
                    !itemImage.isTransparent()
                {
                    await tempCache.cache(image: itemImage, with: item.info)
                } else {
                    failed = true
                }
            }

            return !failed
        }

        let result = await cacheTask.value
        images = await tempCache.images

        return result
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
                .environmentObject(appState)
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
    @EnvironmentObject var appState: AppState
    @EnvironmentObject var itemManager: MenuBarItemManager
    @EnvironmentObject var menuBarManager: MenuBarManager
    @EnvironmentObject var imageCache: IceBarImageCache

    let section: MenuBarSection.Name
    let screen: NSScreen
    let closePanel: () -> Void

    private var items: [MenuBarItem] {
        itemManager.cachedMenuBarItems[section, default: []]
    }

    private var configuration: MenuBarAppearanceConfiguration {
        menuBarManager.appearanceManager.configuration
    }

    private var horizontalPadding: CGFloat {
        configuration.hasRoundedShape ? 7 : 5
    }

    private var verticalPadding: CGFloat {
        configuration.hasRoundedShape ? 2 : 3
    }

    private var clipShape: AnyInsettableShape {
        if configuration.hasRoundedShape {
            AnyInsettableShape(Capsule())
        } else {
            AnyInsettableShape(RoundedRectangle(cornerRadius: 7, style: .circular))
        }
    }

    var body: some View {
        ZStack {
            if configuration.hasShadow {
                styledBody
                    .shadow(color: .black.opacity(0.5), radius: 2.5)
            } else {
                styledBody
            }
            if configuration.hasBorder {
                clipShape
                    .inset(by: configuration.borderWidth / 2)
                    .stroke(lineWidth: configuration.borderWidth)
                    .foregroundStyle(Color(cgColor: configuration.borderColor))
            }
        }
        .padding(5)
        .fixedSize()
    }

    @ViewBuilder
    private var styledBody: some View {
        unstyledBody
            .padding(.horizontal, horizontalPadding)
            .padding(.vertical, verticalPadding)
            .layoutBarStyle(appState: appState)
            .clipShape(clipShape)
    }

    @ViewBuilder
    private var unstyledBody: some View {
        if imageCache.isEmpty(section: section) {
            unableToCapture
                .foregroundStyle(menuBarManager.averageColor?.brightness ?? 0 > 0.67 ? .black : .white)
        } else {
            HStack(spacing: 0) {
                ForEach(items, id: \.windowID) { item in
                    IceBarItemView(item: item, screen: screen, closePanel: closePanel)
                }
            }
        }
    }

    @ViewBuilder
    private var unableToCapture: some View {
        Text("Unable to capture menu bar item images. Try switching spaces.")
            .padding(3)
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
        guard let image = imageCache.images[item.info] else {
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
                .help(item.displayName)
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
