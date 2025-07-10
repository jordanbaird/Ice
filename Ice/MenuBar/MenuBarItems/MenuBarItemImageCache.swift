//
//  MenuBarItemImageCache.swift
//  Ice
//

import Cocoa
import Combine
import OSLog

/// Cache for menu bar item images.
final class MenuBarItemImageCache: ObservableObject {
    /// The cached item images.
    @Published private(set) var images = [MenuBarItemInfo: CGImage]()

    /// Logger for the menu bar item image cache.
    private let logger = Logger(category: "MenuBarItemImageCache")

    /// Queue to run cache operations.
    private let queue = DispatchQueue(label: "MenuBarItemImageCache", qos: .background)

    /// The screen of the cached item images.
    private(set) var screen: NSScreen?

    /// The height of the menu bar of the cached item images.
    private(set) var menuBarHeight: CGFloat?

    /// The shared app state.
    private weak var appState: AppState?

    /// Storage for internal observers.
    private var cancellables = Set<AnyCancellable>()

    /// Sets up the cache.
    @MainActor
    func performSetup(with appState: AppState) {
        self.appState = appState
        configureCancellables()
    }

    /// Configures the internal observers for the cache.
    @MainActor
    private func configureCancellables() {
        var c = Set<AnyCancellable>()

        if let appState {
            Publishers.Merge3(
                // Update every 3 seconds at minimum.
                Timer.publish(every: 3, on: .main, in: .default).autoconnect().replace(with: ()),

                // Update when the active space or screen parameters change.
                Publishers.Merge(
                    NSWorkspace.shared.notificationCenter.publisher(for: NSWorkspace.activeSpaceDidChangeNotification),
                    NotificationCenter.default.publisher(for: NSApplication.didChangeScreenParametersNotification)
                )
                .replace(with: ()),

                // Update when the average menu bar color or cached items change.
                Publishers.Merge(
                    appState.menuBarManager.$averageColorInfo.removeDuplicates().replace(with: ()),
                    appState.itemManager.$itemCache.removeDuplicates().replace(with: ())
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
    private func logSkippingCache(reason: @escaping @autoclosure () -> String) {
        logger.debug("Skipping menu bar item image cache as \(reason(), privacy: .public)")
    }

    /// Returns a Boolean value that indicates whether caching menu bar items
    /// failed for the given section.
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
        for item in items where keys.contains(item.info) {
            return false
        }
        return true
    }

    /// Captures the images of the given menu bar items and returns a dictionary
    /// containing the images, keyed by their menu bar item infos.
    func createImages(for items: [MenuBarItem], screen: NSScreen) -> [MenuBarItemInfo: CGImage] {
        let option: CGWindowImageOption = [.boundsIgnoreFraming, .bestResolution]
        let scale = screen.backingScaleFactor

        var images = [MenuBarItemInfo: CGImage]()
        var excludedItems = [MenuBarItem]()

        compositeCapture: do {
            var windowIDs = [CGWindowID]()
            var storage = [CGWindowID: (MenuBarItem, CGRect)]()
            var boundsUnion = CGRect.null

            for item in items {
                let windowID = item.windowID

                // Don't use item.bounds, it could be out of date.
                guard let bounds = Bridging.getWindowBounds(for: windowID) else {
                    excludedItems.append(item)
                    continue
                }

                windowIDs.append(windowID)
                storage[windowID] = (item, bounds)
                boundsUnion = boundsUnion.union(bounds)
            }

            guard
                let compositeImage = ScreenCapture.captureWindows(windowIDs, option: option),
                CGFloat(compositeImage.width) == boundsUnion.width * scale, // Safety check.
                !compositeImage.isTransparent()
            else {
                excludedItems = items // Exclude all items.
                break compositeCapture
            }

            // Crop out each item from the composite.
            for windowID in windowIDs {
                guard let (item, bounds) = storage[windowID] else {
                    continue
                }

                let cropRect = CGRect(
                    x: (bounds.origin.x - boundsUnion.origin.x) * scale,
                    y: (bounds.origin.y - boundsUnion.origin.y) * scale,
                    width: bounds.width * scale,
                    height: bounds.height * scale
                )

                guard let image = compositeImage.cropping(to: cropRect) else {
                    excludedItems.append(item)
                    continue
                }

                images[item.info] = image
            }
        }

        individualCapture: do {
            if excludedItems.isEmpty {
                break individualCapture // All good!
            }

            logger.notice("Some items were excluded from composite capture: \(excludedItems, privacy: .public)")
            logger.notice("Attempting to capture excluded items individually")

            var failedItems = [MenuBarItem]()

            for item in excludedItems {
                guard
                    let image = ScreenCapture.captureWindow(item.windowID, option: option),
                    !image.isTransparent()
                else {
                    failedItems.append(item)
                    continue
                }
                images[item.info] = image
            }

            if failedItems.isEmpty {
                break individualCapture // All good!
            }

            logger.error("Some items failed capture: \(failedItems, privacy: .public)")
        }

        return images
    }

    /// Captures the images of the menu bar items in the given section and
    /// returns a dictionary containing the images, keyed by their menu bar
    /// item infos.
    func createImages(for section: MenuBarSection.Name, screen: NSScreen) async -> [MenuBarItemInfo: CGImage] {
        guard let appState else {
            return [:]
        }
        let items = await appState.itemManager.itemCache.managedItems(for: section)
        return createImages(for: items, screen: screen)
    }

    /// Updates the cache for the given sections, without checking whether
    /// caching is necessary.
    func updateCacheWithoutChecks(sections: [MenuBarSection.Name]) async {
        guard
            let appState,
            let screen = NSScreen.main
        else {
            return
        }

        var newImages = [MenuBarItemInfo: CGImage]()

        for section in sections {
            guard await !appState.itemManager.itemCache[section].isEmpty else {
                continue
            }
            let sectionImages = await createImages(for: section, screen: screen)
            guard !sectionImages.isEmpty else {
                logger.warning("Failed to update cached menu bar item images for \(section.logString, privacy: .public)")
                continue
            }
            newImages.merge(sectionImages) { (_, new) in new }
        }

        await MainActor.run { [newImages] in
            images.merge(newImages) { (_, new) in new }
        }

        self.screen = screen
        self.menuBarHeight = screen.getMenuBarHeight()
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
