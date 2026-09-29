//
//  MenuBarSearchModel.swift
//  Ice
//

import Cocoa
import Combine
import Ifrit

@MainActor
final class MenuBarSearchModel: ObservableObject {
    enum ItemID: Hashable {
        case header(MenuBarSection.Name)
        case item(MenuBarItemTag)
    }

    @Published var searchText = ""
    @Published var displayedItems = [SectionedListItem<ItemID>]()
    @Published var selection: ItemID?
    @Published private(set) var averageColorInfo: MenuBarAverageColorInfo?

    private var cancellables = Set<AnyCancellable>()

    /// Item images trimmed of their transparent edges, keyed by tag, along
    /// with the images they were trimmed from.
    private var trimmedImages = [MenuBarItemTag: (source: CGImage, image: NSImage?)]()

    let fuse = Fuse(threshold: 0.5)

    func performSetup(with panel: MenuBarSearchPanel) {
        configureCancellables(with: panel)
    }

    private func configureCancellables(with panel: MenuBarSearchPanel) {
        var c = Set<AnyCancellable>()

        Publishers.CombineLatest(
            panel.publisher(for: \.screen),
            panel.publisher(for: \.isVisible)
        )
        .compactMap { screen, isVisible in
            isVisible ? screen : nil
        }
        .sink { [weak self] screen in
            self?.updateAverageColorInfo(for: screen)
        }
        .store(in: &c)

        // Release the trimmed images while the panel is hidden.
        panel.publisher(for: \.isVisible)
            .removeDuplicates()
            .filter { !$0 }
            .sink { [weak self] _ in
                self?.trimmedImages.removeAll()
            }
            .store(in: &c)

        cancellables = c
    }

    /// Returns the given cached item image, trimmed of its transparent edges.
    ///
    /// Trimming scans the image's pixels, so the result is stored until the
    /// image for the tag changes, rather than being redone on every render.
    func trimmedImage(for tag: MenuBarItemTag, from cached: MenuBarItemImageCache.CapturedImage) -> NSImage? {
        if let entry = trimmedImages[tag], entry.source === cached.cgImage {
            return entry.image
        }
        let image: NSImage? = cached.cgImage.trimmingTransparency(around: [.minXEdge, .maxXEdge]).map { trimmed in
            let size = CGSize(
                width: CGFloat(trimmed.width) / cached.scale,
                height: CGFloat(trimmed.height) / cached.scale
            )
            return NSImage(cgImage: trimmed, size: size)
        }
        trimmedImages[tag] = (cached.cgImage, image)
        return image
    }

    private func updateAverageColorInfo(for screen: NSScreen) {
        let windows = WindowInfo.createWindows(option: .onScreen)
        let displayID = screen.displayID

        guard
            let menuBarWindow = WindowInfo.menuBarWindow(from: windows, for: displayID),
            let wallpaperWindow = WindowInfo.wallpaperWindow(from: windows, for: displayID)
        else {
            return
        }

        guard
            let image = ScreenCapture.captureWindows(
                with: [menuBarWindow.windowID, wallpaperWindow.windowID],
                screenBounds: withMutableCopy(of: wallpaperWindow.bounds) { $0.size.height = 1 },
                option: .nominalResolution
            ),
            let color = image.averageColor(option: .ignoreAlpha)
        else {
            return
        }

        let info = MenuBarAverageColorInfo(color: color, source: .menuBarWindow)

        if averageColorInfo != info {
            averageColorInfo = info
        }
    }
}
