//
//  MenuBarItemImageCache.swift
//  Ice
//

import Cocoa
import Combine
import OSLog

/// Cache for menu bar item images.
final class MenuBarItemImageCache: ObservableObject {
    /// A representation of a captured menu bar item image.
    struct CapturedImage: Hashable {
        /// The base image.
        let cgImage: CGImage

        /// The scale factor of the image at the time of capture.
        let scale: CGFloat

        /// The image's size, applying ``scale``.
        var scaledSize: CGSize {
            CGSize(
                width: CGFloat(cgImage.width) / scale,
                height: CGFloat(cgImage.height) / scale
            )
        }

        /// The base image, converted to an `NSImage` and applying ``scale``.
        var nsImage: NSImage {
            NSImage(cgImage: cgImage, size: scaledSize)
        }

        /// Returns whether two captures contain the same pixels. ScreenCaptureKit
        /// creates a new `CGImage` object on every refresh even when the status
        /// glyph did not change; retaining the prior object prevents a needless
        /// Layout redraw every three seconds.
        static func isVisuallyEqual(_ old: CapturedImage, _ new: CapturedImage) -> Bool {
            if old.cgImage === new.cgImage {
                return true
            }
            guard
                old.scale == new.scale,
                old.cgImage.width == new.cgImage.width,
                old.cgImage.height == new.cgImage.height,
                let oldData = old.cgImage.dataProvider?.data,
                let newData = new.cgImage.dataProvider?.data
            else {
                return false
            }
            return CFEqual(oldData, newData)
        }
    }

    /// The result of an image capture operation.
    private struct CaptureResult {
        /// The successfully captured images.
        var images = [MenuBarItemTag: CapturedImage]()

        /// The menu bar items excluded from the capture.
        var excluded = [MenuBarItem]()
    }

    /// The cached item images, keyed by their corresponding tags.
    @Published private(set) var images = [MenuBarItemTag: CapturedImage]()

    /// Logger for the menu bar item image cache.
    private let logger = Logger(category: "MenuBarItemImageCache")

    @MainActor private var isUpdating = false
    @MainActor private var pendingSections = Set<MenuBarSection.Name>()

    /// Image capture options.
    private let captureOption: CGWindowImageOption = [.boundsIgnoreFraming, .bestResolution]

    /// The shared app state.
    private weak var appState: AppState?

    /// Storage for internal observers.
    private var cancellables = Set<AnyCancellable>()

    // MARK: Setup

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
                Task {
                    await self.updateCache()
                }
            }
            .store(in: &c)
        }

        cancellables = c
    }

    // MARK: Capturing Images

    /// Captures a composite image of the given items, then crops out an image
    /// for each item and returns the result.
    private nonisolated func compositeCapture(_ items: [MenuBarItem], scale: CGFloat) -> CaptureResult {
        var result = CaptureResult()

        var windowIDs = [CGWindowID]()
        var storage = [CGWindowID: (MenuBarItem, CGRect)]()
        var boundsUnion = CGRect.null

        for item in items {
            let windowID = item.windowID

            // Don't use `item.bounds`, it could be out of date.
            guard let bounds = Bridging.getWindowBounds(for: windowID) else {
                result.excluded.append(item)
                continue
            }

            windowIDs.append(windowID)
            storage[windowID] = (item, bounds)
            boundsUnion = boundsUnion.union(bounds)
        }

        guard
            let compositeImage = ScreenCapture.captureWindows(with: windowIDs, option: captureOption),
            CGFloat(compositeImage.width) == boundsUnion.width * scale, // Safety check.
            !compositeImage.isTransparent()
        else {
            result.excluded = items // Exclude all items.
            return result
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

            guard
                let image = compositeImage.cropping(to: cropRect),
                !image.isTransparent()
            else {
                result.excluded.append(item)
                continue
            }

            result.images[item.tag] = CapturedImage(cgImage: image, scale: scale)
        }

        return result
    }

    /// Captures an image of each of the given items individually, then
    /// returns the result.
    private nonisolated func individualCapture(_ items: [MenuBarItem], scale: CGFloat) -> CaptureResult {
        var result = CaptureResult()

        for item in items {
            guard
                let image = ScreenCapture.captureWindow(with: item.windowID, option: captureOption),
                !image.isTransparent()
            else {
                result.excluded.append(item)
                continue
            }
            result.images[item.tag] = CapturedImage(cgImage: image, scale: scale)
        }

        return result
    }

    /// Captures the images of the given menu bar items and returns the result.
    private nonisolated func captureImages(of items: [MenuBarItem], scale: CGFloat, appState: AppState) async -> CaptureResult {
        if #available(macOS 27.0, *) {
            let displayID = await appState.itemManager.itemCache.displayID ?? CGMainDisplayID()
            return await captureMacOS27Images(
                of: items,
                displayID: displayID
            )
        }

        // Use individual capture after a move operation, since composite capture
        // doesn't account for overlapping items.
        if await appState.itemManager.lastMoveOperationOccurred(within: .seconds(2)) {
            logger.debug("Capturing individually due to recent item movement")
            return individualCapture(items, scale: scale)
        }

        let compositeResult = compositeCapture(items, scale: scale)

        if compositeResult.excluded.isEmpty {
            return compositeResult // All items captured successfully.
        }

        logger.notice(
            """
            Some items were excluded from composite capture. Attempting to capture \
            excluded items individually: \(compositeResult.excluded, privacy: .public)
            """
        )

        var individualResult = individualCapture(compositeResult.excluded, scale: scale)

        // Merge the successfully captured images from each result. Keep excluded
        // items as part of the result, so they can be logged elsewhere.
        individualResult.images.merge(compositeResult.images) { (_, new) in new }

        return individualResult
    }

    /// Captures the exact, composited menu-bar pixels while Layout is open.
    @available(macOS 27.0, *)
    private nonisolated func captureMacOS27Images(
        of items: [MenuBarItem],
        displayID: CGDirectDisplayID
    ) async -> CaptureResult {
        let capturable = items.filter { !$0.isControlItem || $0.tag == .visibleControlItem }
        guard !capturable.isEmpty else { return CaptureResult() }

        var result = CaptureResult()

        if ScreenCapture.cachedCheckPermissions() {
            // Layout reveals all sections before this pass. Refresh only the
            // participating owners so crop geometry follows each item's live
            // position without another full running-application AX scan.
            let sourcePIDs = Set(capturable.map { $0.sourcePID ?? $0.ownerPID })
            let namespaces = Set(capturable.map(\.tag.namespace))
            let refreshedItems = await Task.detached(priority: .userInitiated) {
                MacOS27MenuBarItemProvider.menuBarItems(
                    sourcePIDs: sourcePIDs,
                    namespaces: namespaces
                )
            }.value
            let refreshedByTag = Dictionary(
                refreshedItems.map { ($0.tag, $0) },
                uniquingKeysWith: { current, _ in current }
            )
            let liveItems = capturable.compactMap { refreshedByTag[$0.tag] }
            if let capture = await ScreenCapture.captureMenuBarDisplayStrip(displayID: displayID),
               isPlausibleMacOS27Capture(capture) {
                // A drag can occur while the screenshot is being produced.
                // Only associate pixels with an item whose frame stayed put.
                let afterCapture = await Task.detached(priority: .userInitiated) {
                    MacOS27MenuBarItemProvider.menuBarItems(sourcePIDs: sourcePIDs, namespaces: namespaces)
                }.value
                let stableItems = liveItems.filter { item in
                    afterCapture.first(matching: item.tag)?.bounds == item.bounds
                }
                appendMacOS27Crops(
                    for: stableItems, from: capture, into: &result
                )
            }
        }

        // Never substitute an application icon or a guessed symbol for the
        // actual menu-bar glyph. A missed capture retains the last exact image.
        result.excluded = capturable.filter { result.images[$0.tag] == nil }
        logger.debug("macOS 27 thumbnails: \(result.images.count, privacy: .public) exact, \(result.excluded.count, privacy: .public) excluded")
        return result
    }

    @available(macOS 27.0, *)
    private nonisolated func isPlausibleMacOS27Capture(
        _ capture: ScreenCapture.MenuBarCapture
    ) -> Bool {
        guard
            capture.scale.isFinite,
            capture.scale > 0,
            capture.windowFrame.width.isFinite,
            capture.windowFrame.height.isFinite,
            capture.windowFrame.width > 0,
            capture.windowFrame.height > 0
        else {
            return false
        }
        return abs(CGFloat(capture.image.width) - capture.windowFrame.width * capture.scale) <= 3 &&
            abs(CGFloat(capture.image.height) - capture.windowFrame.height * capture.scale) <= 3
    }

    /// Crops one menu-bar capture into exact per-item images. Duplicate AX
    /// frames are rejected for both owners, preventing one glyph from being
    /// shown under several app names while MenuBarAgent is reflowing.
    @available(macOS 27.0, *)
    private nonisolated func appendMacOS27Crops(
        for items: [MenuBarItem],
        from capture: ScreenCapture.MenuBarCapture,
        into result: inout CaptureResult
    ) {
        let imageBounds = CGRect(
            x: 0,
            y: 0,
            width: capture.image.width,
            height: capture.image.height
        )
        var cropOwners = [CGRect: MenuBarItemTag]()

        for item in items {
            let bounds = item.bounds
            guard
                !bounds.isNull,
                !bounds.isEmpty,
                bounds.width >= 8,
                bounds.width <= 200,
                bounds.height > 0,
                bounds.height <= 40,
                capture.windowFrame.intersects(bounds)
            else {
                continue
            }

            let expectedCropRect = CGRect(
                x: (bounds.minX - capture.windowFrame.minX) * capture.scale,
                y: (bounds.minY - capture.windowFrame.minY) * capture.scale,
                width: bounds.width * capture.scale,
                height: bounds.height * capture.scale
            ).integral
            let cropRect = expectedCropRect.intersection(imageBounds)
            guard
                !cropRect.isNull,
                !cropRect.isEmpty,
                cropRect.minX - expectedCropRect.minX <= 1,
                cropRect.minY - expectedCropRect.minY <= 1,
                expectedCropRect.maxX - cropRect.maxX <= 1,
                expectedCropRect.maxY - cropRect.maxY <= 1
            else {
                continue
            }

            if let priorTag = cropOwners[cropRect] {
                result.images.removeValue(forKey: priorTag)
                continue
            }

            guard let image = capture.image.cropping(to: cropRect),
                  !image.isTransparent(alphaThreshold: 0.05) else { continue }

            cropOwners[cropRect] = item.tag
            result.images[item.tag] = CapturedImage(
                cgImage: image,
                scale: capture.scale
            )
        }
    }

    /// Captures the images of the menu bar items in the given section and returns
    /// a dictionary containing the images, keyed by their menu bar item tags.
    private func captureImages(for section: MenuBarSection.Name, scale: CGFloat, appState: AppState) async -> [MenuBarItemTag: CapturedImage] {
        let items = await appState.itemManager.itemCache.managedItems(for: section)
        let captureResult = await captureImages(of: items, scale: scale, appState: appState)
        if !captureResult.excluded.isEmpty {
            logger.error("Some items failed capture: \(captureResult.excluded, privacy: .public)")
        }
        return captureResult.images
    }

    // MARK: Update Cache

    /// Updates the cache for the given sections, without checking whether
    /// caching is necessary.
    @MainActor
    func updateCacheWithoutChecks(sections: [MenuBarSection.Name]) async {
        guard !Task.isCancelled else { return }
        pendingSections.formUnion(sections)
        guard !isUpdating else { return }
        isUpdating = true
        defer {
            isUpdating = false
            pendingSections.removeAll()
        }
        // Activation, Layout appearance and the timer share one capture. A
        // request that arrives during it is coalesced into the next pass.
        while !pendingSections.isEmpty, !Task.isCancelled {
            let requested = Array(pendingSections)
            pendingSections.removeAll()
            await captureAndUpdate(sections: requested)
        }
    }

    @MainActor
    private func captureAndUpdate(sections: [MenuBarSection.Name]) async {
        guard let appState else {
            return
        }

        guard
            let displayID = appState.itemManager.itemCache.displayID,
            let screen = NSScreen.screens.first(where: { $0.displayID == displayID })
        else {
            return
        }

        let scale = screen.backingScaleFactor
        var newImages = [MenuBarItemTag: CapturedImage]()
        let controller = appState.menuBarManager.macOS27Controller
        let generation = controller.interactionGeneration

        if #available(macOS 27.0, *) {
            guard controller.isLayoutEditing, !controller.isReorderInProgress else { return }
            let allItems = sections.flatMap { section in
                appState.itemManager.itemCache.managedItems(for: section)
            }
            let result = await captureMacOS27Images(
                of: allItems,
                displayID: displayID
            )
            newImages = result.images
        } else {
            guard appState.hasPermission(.screenRecording) else { return }

            for section in sections {
                guard !appState.itemManager.itemCache[section].isEmpty else {
                    continue
                }

                let sectionImages = await captureImages(for: section, scale: scale, appState: appState)

                guard !sectionImages.isEmpty else {
                    logger.warning("Failed item image cache for \(section.logString, privacy: .public)")
                    continue
                }

                newImages.merge(sectionImages) { (_, new) in new }
            }
        }

        guard !Task.isCancelled, appState.itemManager.itemCache.displayID == displayID else { return }
        if #available(macOS 27.0, *) {
            guard controller.isLayoutEditing, !controller.isReorderInProgress,
                  controller.interactionGeneration == generation else { return }
        }
        let validTags = Set(appState.itemManager.itemCache.managedItems.map(\.tag))
        var updatedImages = images.filter { validTags.contains($0.key) }
        updatedImages.merge(newImages) { old, new in
            if CapturedImage.isVisuallyEqual(old, new) {
                return old
            }
            return new
        }
        // Publishing an equal dictionary still wakes every Layout tile.
        // Assign only when content really changed so the periodic refresh
        // cannot produce a redraw pulse.
        if updatedImages != images {
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
            guard
                await appState.navigationState.isAppFrontmost,
                await appState.navigationState.isSettingsPresented,
                await appState.navigationState.settingsNavigationIdentifier == .menuBarLayout
            else {
                return
            }
        }

        guard await !appState.itemManager.lastMoveOperationOccurred(within: .seconds(1)) else {
            logger.debug("Skipping item image cache due to recent item movement")
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

    // MARK: Cache Failed

    /// Returns a Boolean value that indicates whether caching menu bar items
    /// failed for the given section.
    @MainActor
    func cacheFailed(for section: MenuBarSection.Name) -> Bool {
        if #unavailable(macOS 27.0) {
            guard ScreenCapture.cachedCheckPermissions() else { return true }
        }
        let items = appState?.itemManager.itemCache[section] ?? []
        guard !items.isEmpty else {
            return false
        }
        let keys = Set(images.keys)
        for item in items where keys.contains(item.tag) {
            return false
        }
        return true
    }
}
