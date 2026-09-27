//
//  MenuBarItemImageCache.swift
//  Ice
//

import Cocoa
import Combine

/// Cache for menu bar item images.
final class MenuBarItemImageCache: ObservableObject {
    /// 按真实窗口编号缓存，避免托管图标同名时互相覆盖。
    @Published private(set) var images = [CGWindowID: CGImage]()

    /// The screen of the cached item images.
    private(set) var screen: NSScreen?

    /// The height of the menu bar of the cached item images.
    private(set) var menuBarHeight: CGFloat?

    /// The shared app state.
    private weak var appState: AppState?

    /// Storage for internal observers.
    private var cancellables = Set<AnyCancellable>()

    /// Creates a cache with the given app state.
    init(appState: AppState) {
        self.appState = appState
    }

    /// Sets up the cache.
    @MainActor
    func performSetup() {
        configureCancellables()
    }

    /// Configures the internal observers for the cache.
    @MainActor
    private func configureCancellables() {
        var c = Set<AnyCancellable>()

        if let appState {
            Publishers.Merge3(
                // Update every 3 seconds at minimum.
                Timer.publish(every: 3, on: .main, in: .default).autoconnect().mapToVoid(),

                // Update when the active space or screen parameters change.
                Publishers.Merge(
                    NSWorkspace.shared.notificationCenter.publisher(for: NSWorkspace.activeSpaceDidChangeNotification),
                    NotificationCenter.default.publisher(for: NSApplication.didChangeScreenParametersNotification)
                )
                .mapToVoid(),

                // Update when the average menu bar color or cached items change.
                Publishers.Merge(
                    appState.menuBarManager.$averageColorInfo.removeDuplicates().mapToVoid(),
                    appState.itemManager.$itemCache.removeDuplicates().mapToVoid()
                )
            )
            .throttle(for: 0.5, scheduler: DispatchQueue.main, latest: true)
            .sink { [weak self] in
                guard let self else {
                    return
                }
                Task.detached {
                    if ScreenCapture.cachedCheckPermissions() {
                        await self.updateCache()
                    }
                }
            }
            .store(in: &c)
        }

        cancellables = c
    }

    /// Logs a reason for skipping the cache.
    private func logSkippingCache(reason: String) {
        Logger.imageCache.debug("Skipping menu bar item image cache as \(reason)")
    }

    /// Returns a Boolean value that indicates whether caching menu bar items failed for
    /// the given section.
    @MainActor
    func cacheFailed(for section: MenuBarSection.Name) -> Bool {
        guard ScreenCapture.cachedCheckPermissions() else {
            return true
        }
        let items = appState?.itemManager.itemCache[section] ?? []
        guard !items.isEmpty else {
            return false
        }
        let keys = Set(images.keys)
        for item in items where keys.contains(item.windowID) {
            return false
        }
        return true
    }

    /// 检查全部待显示项目，而不是只检查是否抓到任意一张图片。
    @MainActor
    func hasImages(for section: MenuBarSection.Name) -> Bool {
        guard let items = appState?.itemManager.itemCache.managedItems(for: section), !items.isEmpty else {
            return false
        }
        return items.allSatisfy { images[$0.windowID] != nil }
    }

    /// 抓取菜单栏图标，并以真实窗口编号索引。
    func createImages(for section: MenuBarSection.Name, screen: NSScreen) async -> [CGWindowID: CGImage] {
        guard let appState else {
            return [:]
        }

        let items = await appState.itemManager.itemCache[section]

        var images = [CGWindowID: CGImage]()
        let backingScaleFactor = screen.backingScaleFactor
        let displayBounds = CGDisplayBounds(screen.displayID)
        let option: CGWindowImageOption = [.boundsIgnoreFraming, .bestResolution]
        let defaultItemThickness = NSStatusBar.system.thickness * backingScaleFactor

        var itemFrames = [CGWindowID: CGRect]()
        var windowIDs = [CGWindowID]()
        var frame = CGRect.null

        for item in items {
            let windowID = item.windowID
            guard
                // Use the most up-to-date window frame.
                let itemFrame = Bridging.getWindowFrame(for: windowID),
                itemFrame.minY >= displayBounds.minY,
                itemFrame.minY < displayBounds.minY + (screen.getMenuBarHeight() ?? NSStatusBar.system.thickness),
                itemFrame.width > 0, itemFrame.height > 0
            else {
                continue
            }
            itemFrames[windowID] = itemFrame
            windowIDs.append(windowID)
            frame = frame.union(itemFrame)
        }

        guard !windowIDs.isEmpty else { return [:] }

        // Tahoe 的离屏托管窗口逐项抓取，避免合成图只包含部分项目。
        let useComposite: Bool
        if #available(macOS 26.0, *) { useComposite = false } else { useComposite = true }
        if useComposite,
            let compositeImage = ScreenCapture.captureWindows(windowIDs, option: option),
            CGFloat(compositeImage.width) == frame.width * backingScaleFactor
        {
            for windowID in windowIDs {
                guard
                    let itemFrame = itemFrames[windowID]
                else {
                    continue
                }

                let frame = CGRect(
                    x: (itemFrame.origin.x - frame.origin.x) * backingScaleFactor,
                    y: (itemFrame.origin.y - frame.origin.y) * backingScaleFactor,
                    width: itemFrame.width * backingScaleFactor,
                    height: itemFrame.height * backingScaleFactor
                )

                guard let itemImage = compositeImage.cropping(to: frame) else {
                    continue
                }

                images[windowID] = itemImage
            }
        }

        // 合成图裁剪失败的单个项目也需要补抓。
        for windowID in windowIDs where images[windowID] == nil {
            guard let itemImage = ScreenCapture.captureWindow(windowID, option: option) else { continue }
            let height = min(CGFloat(itemImage.height), defaultItemThickness)
            let crop = CGRect(
                x: 0, y: (CGFloat(itemImage.height) - height) / 2,
                width: CGFloat(itemImage.width), height: height
            )
            images[windowID] = itemImage.cropping(to: crop)
        }

        return images
    }

    /// Updates the cache for the given sections, without checking whether caching is necessary.
    func updateCacheWithoutChecks(sections: [MenuBarSection.Name], on targetScreen: NSScreen? = nil) async {
        guard
            let appState,
            let screen = targetScreen ?? NSScreen.main
        else {
            return
        }

        var newImages = [CGWindowID: CGImage]()

        for section in sections {
            guard await !appState.itemManager.itemCache[section].isEmpty else {
                continue
            }
            let sectionImages = await createImages(for: section, screen: screen)
            guard !sectionImages.isEmpty else {
                Logger.imageCache.warning("Update image cache failed for \(section.logString)")
                continue
            }
            newImages.merge(sectionImages) { (_, new) in new }
        }

        await MainActor.run { [newImages] in
            let activeWindowIDs = Set(appState.itemManager.itemCache.allItems.map(\.windowID))
            var updatedImages = images.filter { activeWindowIDs.contains($0.key) }
            updatedImages.merge(newImages.filter { activeWindowIDs.contains($0.key) }) { (_, new) in new }
            self.screen = screen
            self.menuBarHeight = screen.getMenuBarHeight()
            images = updatedImages
        }
    }

    /// Updates the cache for the given sections, if necessary.
    func updateCache(sections: [MenuBarSection.Name]) async {
        guard let appState else {
            return
        }

        let isIceBarPresented = await appState.navigationState.isIceBarPresented
        let isSearchPresented = await appState.navigationState.isSearchPresented

        if !isIceBarPresented && !isSearchPresented {
            guard await appState.navigationState.isAppFrontmost else {
                logSkippingCache(reason: "Ice Bar not visible, app not frontmost")
                return
            }
            guard await appState.navigationState.isSettingsPresented else {
                logSkippingCache(reason: "Ice Bar not visible, Settings not visible")
                return
            }
            guard case .menuBarLayout = await appState.navigationState.settingsNavigationIdentifier else {
                logSkippingCache(reason: "Ice Bar not visible, Settings visible but not on Menu Bar Layout")
                return
            }
        }

        guard await !appState.itemManager.isMovingItem else {
            logSkippingCache(reason: "an item is currently being moved")
            return
        }

        guard await !appState.itemManager.itemHasRecentlyMoved else {
            logSkippingCache(reason: "an item was recently moved")
            return
        }

        await updateCacheWithoutChecks(sections: sections)
    }

    /// Updates the cache for all sections, if necessary.
    func updateCache() async {
        guard let appState else {
            return
        }

        let isIceBarPresented = await appState.navigationState.isIceBarPresented
        let isSearchPresented = await appState.navigationState.isSearchPresented
        let isSettingsPresented = await appState.navigationState.isSettingsPresented

        var sectionsNeedingDisplay = [MenuBarSection.Name]()
        if isSettingsPresented || isSearchPresented {
            sectionsNeedingDisplay = MenuBarSection.Name.allCases
        } else if
            isIceBarPresented,
            let section = await appState.menuBarManager.iceBarPanel.currentSection
        {
            sectionsNeedingDisplay.append(section)
        }

        await updateCache(sections: sectionsNeedingDisplay)
    }
}

// MARK: - Logger

private extension Logger {
    static let imageCache = Logger(category: "MenuBarItemImageCache")
}
