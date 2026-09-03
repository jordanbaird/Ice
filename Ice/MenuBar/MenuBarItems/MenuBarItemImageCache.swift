//
//  MenuBarItemImageCache.swift
//  Ice
//

import Cocoa
import Combine

/// Cache for menu bar item images.
@MainActor
final class MenuBarItemImageCache: ObservableObject {
    /// The cached item images.
    @Published private(set) var images = [MenuBarItemInfo: CGImage]()

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
    func performSetup() {
        configureCancellables()
    }

    /// Configures the internal observers for the cache.
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
            .throttle(for: 0.5, scheduler: DispatchQueue.main, latest: false)
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
    func cacheFailed(for section: MenuBarSection.Name) -> Bool {
        guard ScreenCapture.cachedCheckPermissions() else {
            return true
        }
        let items = appState?.itemManager.itemCache[section] ?? []
        guard !items.isEmpty else {
            return false
        }
        let keys = Set(images.keys)
        for item in items where keys.contains(item.info) {
            return false
        }
        return true
    }

    /// Captures the images of the current menu bar items and returns a dictionary containing
    /// the images, keyed by the current menu bar item infos.
    func createImages(for section: MenuBarSection.Name, screen: NSScreen) async -> [MenuBarItemInfo: CGImage] {
        guard let appState else {
            return [:]
        }

        let items = appState.itemManager.itemCache[section]

        let backingScaleFactor = screen.backingScaleFactor
        let displayBounds = CGDisplayBounds(screen.displayID)
        let defaultItemThickness = NSStatusBar.system.thickness * backingScaleFactor

        var itemInfos = [CGWindowID: MenuBarItemInfo]()
        var itemFrames = [CGWindowID: CGRect]()
        var windowIDs = [CGWindowID]()
        var frame = CGRect.null

        for item in items {
            let windowID = item.windowID
            guard
                // Use the most up-to-date window frame.
                let itemFrame = Bridging.getWindowFrame(for: windowID),
                itemFrame.minY == displayBounds.minY
            else {
                continue
            }
            itemInfos[windowID] = item.info
            itemFrames[windowID] = itemFrame
            windowIDs.append(windowID)
            frame = frame.union(itemFrame)
        }

        return await Self.captureImages(
            windowIDs: windowIDs,
            itemInfos: itemInfos,
            itemFrames: itemFrames,
            frame: frame,
            backingScaleFactor: backingScaleFactor,
            defaultItemThickness: defaultItemThickness
        )
    }

    /// Captures the images of the given menu bar item windows and returns a dictionary
    /// containing the images, keyed by the corresponding menu bar item infos.
    ///
    /// This function is nonisolated so that the capture work is performed off the
    /// main thread.
    private nonisolated static func captureImages(
        windowIDs: [CGWindowID],
        itemInfos: [CGWindowID: MenuBarItemInfo],
        itemFrames: [CGWindowID: CGRect],
        frame: CGRect,
        backingScaleFactor: CGFloat,
        defaultItemThickness: CGFloat
    ) async -> [MenuBarItemInfo: CGImage] {
        let option: CGWindowImageOption = [.boundsIgnoreFraming, .bestResolution]
        var images = [MenuBarItemInfo: CGImage]()

        if
            let compositeImage = ScreenCapture.captureWindows(windowIDs, option: option),
            CGFloat(compositeImage.width) == frame.width * backingScaleFactor
        {
            for windowID in windowIDs {
                guard
                    let itemInfo = itemInfos[windowID],
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

                images[itemInfo] = itemImage
            }
        } else {
            Logger.imageCache.warning("Composite image capture failed. Attempting to capturing items individually.")

            for windowID in windowIDs {
                guard
                    let itemInfo = itemInfos[windowID],
                    let itemFrame = itemFrames[windowID]
                else {
                    continue
                }

                let frame = CGRect(
                    x: 0,
                    y: ((itemFrame.height * backingScaleFactor) / 2) - (defaultItemThickness / 2),
                    width: itemFrame.width * backingScaleFactor,
                    height: defaultItemThickness
                )

                guard
                    let itemImage = ScreenCapture.captureWindow(windowID, option: option),
                    let croppedImage = itemImage.cropping(to: frame)
                else {
                    continue
                }

                images[itemInfo] = croppedImage
            }
        }

        return images
    }

    /// Updates the cache for the given sections, without checking whether caching is necessary.
    func updateCacheWithoutChecks(sections: [MenuBarSection.Name]) async {
        guard
            let appState,
            let screen = NSScreen.main
        else {
            return
        }

        var newImages = [MenuBarItemInfo: CGImage]()

        for section in sections {
            guard !appState.itemManager.itemCache[section].isEmpty else {
                continue
            }
            let sectionImages = await createImages(for: section, screen: screen)
            guard !sectionImages.isEmpty else {
                Logger.imageCache.warning("Update image cache failed for \(section.logString)")
                continue
            }
            newImages.merge(sectionImages) { (_, new) in new }
        }

        images.merge(newImages) { (_, new) in new }

        self.screen = screen
        self.menuBarHeight = screen.getMenuBarHeight()
    }

    /// Updates the cache for the given sections, if necessary.
    func updateCache(sections: [MenuBarSection.Name]) async {
        guard let appState else {
            return
        }

        let isIceBarPresented = appState.navigationState.isIceBarPresented
        let isSearchPresented = appState.navigationState.isSearchPresented

        if !isIceBarPresented && !isSearchPresented {
            guard appState.navigationState.isAppFrontmost else {
                logSkippingCache(reason: "Ice Bar not visible, app not frontmost")
                return
            }
            guard appState.navigationState.isSettingsPresented else {
                logSkippingCache(reason: "Ice Bar not visible, Settings not visible")
                return
            }
            guard case .menuBarLayout = appState.navigationState.settingsNavigationIdentifier else {
                logSkippingCache(reason: "Ice Bar not visible, Settings visible but not on Menu Bar Layout")
                return
            }
        }

        guard !appState.itemManager.isMovingItem else {
            logSkippingCache(reason: "an item is currently being moved")
            return
        }

        guard !appState.itemManager.itemHasRecentlyMoved else {
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

        let isIceBarPresented = appState.navigationState.isIceBarPresented
        let isSearchPresented = appState.navigationState.isSearchPresented
        let isSettingsPresented = appState.navigationState.isSettingsPresented

        var sectionsNeedingDisplay = [MenuBarSection.Name]()
        if isSettingsPresented || isSearchPresented {
            sectionsNeedingDisplay = MenuBarSection.Name.allCases
        } else if
            isIceBarPresented,
            let section = appState.menuBarManager.iceBarPanel.currentSection
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
