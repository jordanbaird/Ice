//
//  MenuBarItemImageCache.swift
//  Ice
//

import Cocoa
import Combine
import OSLog

@MainActor
class MenuBarItemImageCache: ObservableObject {
    /// The cached item images.
    @Published private(set) var images = [MenuBarItemInfo: CGImage]()

    /// The screen of the cached item images.
    private(set) var screen: NSScreen?

    /// The height of the menu bar of the cached item images.
    private(set) var menuBarHeight: CGFloat?

    private weak var appState: AppState?

    private var cancellables = Set<AnyCancellable>()

    init(appState: AppState) {
        self.appState = appState
    }

    func performSetup() {
        configureCancellables()
    }

    private func configureCancellables() {
        var c = Set<AnyCancellable>()

        if let appState {
            Publishers.Merge3(
                // update every 3 seconds at minimum
                Timer.publish(every: 3, on: .main, in: .default).autoconnect().mapToVoid(),

                // update when the active space or screen parameters change
                Publishers.Merge(
                    NSWorkspace.shared.notificationCenter.publisher(for: NSWorkspace.activeSpaceDidChangeNotification),
                    NotificationCenter.default.publisher(for: NSApplication.didChangeScreenParametersNotification)
                )
                .mapToVoid(),

                // update when the average menu bar color or cached items change
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
                Task {
                    await self.updateCache()
                }
            }
            .store(in: &c)
        }

        cancellables = c
    }

    func cacheFailed(for section: MenuBarSection.Name) -> Bool {
        let items = appState?.itemManager.itemCache.allItems(for: section) ?? []
        guard !items.isEmpty else {
            return false
        }
        let keys = Set(images.keys)
        for item in items where keys.contains(item.info) {
            return false
        }
        return true
    }

    func createImages(for section: MenuBarSection.Name, screen: NSScreen) async -> [MenuBarItemInfo: CGImage] {
        actor TempCache {
            private(set) var images = [MenuBarItemInfo: CGImage]()

            func cache(image: CGImage, with info: MenuBarItemInfo) {
                images[info] = image
            }
        }

        guard let appState else {
            return [:]
        }

        let items = appState.itemManager.itemCache.allItems(for: section)

        let tempCache = TempCache()
        let backingScaleFactor = screen.backingScaleFactor
        let displayBounds = CGDisplayBounds(screen.displayID)
        let option: CGWindowImageOption = [.boundsIgnoreFraming, .bestResolution]
        let defaultItemThickness = NSStatusBar.system.thickness * backingScaleFactor

        let cacheTask = Task.detached {
            var itemInfos = [CGWindowID: MenuBarItemInfo]()
            var itemFrames = [CGWindowID: CGRect]()
            var windowIDs = [CGWindowID]()
            var frame = CGRect.null

            for item in items {
                let windowID = item.windowID
                guard
                    // use the most up-to-date window frame
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

            if
                let compositeImage = Bridging.captureWindows(windowIDs, option: option),
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

                    await tempCache.cache(image: itemImage, with: itemInfo)
                }
            } else {
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
                        let itemImage = Bridging.captureWindow(windowID, option: option),
                        let croppedImage = itemImage.cropping(to: frame)
                    else {
                        continue
                    }

                    await tempCache.cache(image: croppedImage, with: itemInfo)
                }
            }
        }

        await cacheTask.value
        return await tempCache.images
    }

    func updateCacheWithoutChecks(sections: [MenuBarSection.Name]) async {
        guard
            let appState,
            let screen = NSScreen.main
        else {
            return
        }
        var images = images
        for section in sections {
            guard !appState.itemManager.itemCache.allItems(for: section).isEmpty else {
                continue
            }
            let sectionImages = await createImages(for: section, screen: screen)
            guard !sectionImages.isEmpty else {
                Logger.imageCache.warning("Update image cache failed for \(section.logString)")
                continue
            }
            images.merge(sectionImages) { (_, new) in new }
        }
        self.images = images
        self.screen = screen
        self.menuBarHeight = screen.getMenuBarHeight()
    }

    func updateCache() async {
        guard let appState else {
            return
        }

        if !appState.navigationState.isIceBarPresented {
            guard appState.navigationState.isSettingsPresented else {
                Logger.imageCache.debug("Skipping image cache as Ice Bar not visible, Settings not visible")
                return
            }
            guard case .menuBarItems = appState.navigationState.settingsNavigationIdentifier else {
                Logger.imageCache.debug("Skipping image cache as Ice Bar not visible, Settings visible but not on Menu Bar Items pane")
                return
            }
        }

        if let lastItemMoveStartDate = appState.itemManager.lastItemMoveStartDate {
            guard Date.now.timeIntervalSince(lastItemMoveStartDate) > 3 else {
                Logger.imageCache.debug("Skipping image cache as an item was recently moved")
                return
            }
        }

        var sectionsNeedingDisplay = [MenuBarSection.Name]()
        if appState.navigationState.isSettingsPresented {
            sectionsNeedingDisplay = MenuBarSection.Name.allCases
        } else if
            appState.navigationState.isIceBarPresented,
            let section = appState.menuBarManager.iceBarPanel.currentSection
        {
            sectionsNeedingDisplay.append(section)
        }

        await updateCacheWithoutChecks(sections: sectionsNeedingDisplay)
    }
}

private extension Logger {
    static let imageCache = Logger(category: "MenuBarItemImageCache")
}
