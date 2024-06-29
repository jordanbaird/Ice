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
            Publishers.Merge(
                // update when the active space or screen parameters change
                Publishers.Merge(
                    NSWorkspace.shared.notificationCenter.publisher(for: NSWorkspace.activeSpaceDidChangeNotification),
                    NotificationCenter.default.publisher(for: NSApplication.didChangeScreenParametersNotification)
                )
                .mapToVoid(),

                // update when the average menu bar color or cached items change
                Publishers.Merge(
                    appState.menuBarManager.$averageColorInfo.removeDuplicates().mapToVoid(),
                    appState.itemManager.$menuBarItemCache.removeDuplicates().mapToVoid()
                )
            )
            .receive(on: DispatchQueue.main)
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

        Timer.publish(every: 3, on: .main, in: .default)
            .autoconnect()
            .sink { [weak self] _ in
                guard let self else {
                    return
                }
                Task {
                    await self.updateCache()
                }
            }
            .store(in: &c)

        cancellables = c
    }

    func cacheFailed(for section: MenuBarSection.Name) -> Bool {
        let items = appState?.itemManager.menuBarItemCache.allItems(for: section) ?? []
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

        let items = appState.itemManager.menuBarItemCache.allItems(for: section)

        let tempCache = TempCache()
        let backingScaleFactor = screen.backingScaleFactor
        let displayBounds = CGDisplayBounds(screen.displayID)
        let option: CGWindowImageOption = [.boundsIgnoreFraming, .bestResolution]
        let defaultItemThickness = NSStatusBar.system.thickness * backingScaleFactor

        let cacheTask = Task.detached {
            var windowIDs = [CGWindowID]()
            var frame = CGRect.null

            let filteredItems = items.lazy.filter { item in
                item.frame.minY == displayBounds.minY
            }

            for item in filteredItems {
                windowIDs.append(item.windowID)
                frame = frame.union(item.frame)
            }

            if
                let compositeImage = Bridging.captureWindows(windowIDs, option: option),
                CGFloat(compositeImage.width) == frame.width * backingScaleFactor
            {
                var start: CGFloat = 0

                for item in filteredItems {
                    let width = item.frame.width * backingScaleFactor
                    let height = item.frame.height * backingScaleFactor
                    let frame = CGRect(
                        x: start,
                        y: (height / 2) - (defaultItemThickness / 2),
                        width: width,
                        height: defaultItemThickness
                    )

                    defer {
                        start += width
                    }

                    guard let itemImage = compositeImage.cropping(to: frame) else {
                        continue
                    }

                    await tempCache.cache(image: itemImage, with: item.info)
                }
            } else {
                for item in filteredItems {
                    let width = item.frame.width * backingScaleFactor
                    let height = item.frame.height * backingScaleFactor
                    let frame = CGRect(
                        x: 0,
                        y: (height / 2) - (defaultItemThickness / 2),
                        width: width,
                        height: defaultItemThickness
                    )

                    guard
                        let itemImage = Bridging.captureWindow(item.windowID, option: option),
                        let croppedImage = itemImage.cropping(to: frame)
                    else {
                        continue
                    }

                    await tempCache.cache(image: croppedImage, with: item.info)
                }
            }
        }

        await cacheTask.value
        return await tempCache.images
    }

    func updateCache() async {
        guard let appState else {
            return
        }
        guard !appState.itemManager.isMovingItem else {
            Logger.imageCache.info("Item manager is moving item, so deferring image cache")
            return
        }
        guard let screen = NSScreen.main else {
            return
        }
        var sectionsNeedingDisplay = [MenuBarSection.Name]()
        if
            let settingsWindow = appState.settingsWindow,
            settingsWindow.isVisible
        {
            sectionsNeedingDisplay = MenuBarSection.Name.allCases
        } else if let section = appState.menuBarManager.iceBarPanel.currentSection {
            sectionsNeedingDisplay.append(section)
        }
        for section in sectionsNeedingDisplay {
            guard !appState.itemManager.menuBarItemCache.allItems(for: section).isEmpty else {
                continue
            }
            let sectionImages = await createImages(for: section, screen: screen)
            guard !sectionImages.isEmpty else {
                Logger.imageCache.warning("Update cache failed for \(section.logString)")
                continue
            }
            images.merge(sectionImages) { (_, new) in new }
        }
        self.screen = screen
        self.menuBarHeight = screen.getMenuBarHeight()
    }
}

private extension Logger {
    static let imageCache = Logger(category: "MenuBarItemImageCache")
}
