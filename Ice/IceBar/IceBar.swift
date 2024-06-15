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
    @Published private var pinnedLocation: IceBarPinnedLocation?

    private weak var appState: AppState?

    private var imageCache = IceBarImageCache()

    private let encoder = JSONEncoder()

    private let decoder = JSONDecoder()

    private(set) var currentSection: MenuBarSection.Name?

    private var cancellables = Set<AnyCancellable>()

    var isPinned: Bool {
        pinnedLocation != nil
    }

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
        self.collectionBehavior = [.fullScreenAuxiliary, .ignoresCycle, .moveToActiveSpace]
        performSetup()
        configureCancellables()
    }

    private func performSetup() {
        Defaults.ifPresent(key: .iceBarPinnedLocation) { data in
            do {
                pinnedLocation = try decoder.decode(IceBarPinnedLocation.self, from: data)
            } catch {
                Logger.iceBar.error("Error decoding pinned location: \(error)")
            }
        }
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

        $pinnedLocation
            .receive(on: DispatchQueue.main)
            .sink { [weak self] pinnedLocation in
                self?.isMovable = pinnedLocation == nil
            }
            .store(in: &c)

        $pinnedLocation
            .receive(on: DispatchQueue.main)
            .sink { [weak self] pinnedLocation in
                guard let self else {
                    return
                }
                guard let pinnedLocation else {
                    Defaults.removeObject(forKey: .iceBarPinnedLocation)
                    return
                }
                do {
                    let data = try encoder.encode(pinnedLocation)
                    Defaults.set(data, forKey: .iceBarPinnedLocation)
                } catch {
                    Logger.iceBar.error("Error encoding pinned location: \(error)")
                }
            }
            .store(in: &c)

        cancellables = c
    }

    private func updateOrigin(for screen: NSScreen) {
        if let pinnedLocation {
            let point = pinnedLocation.point(frame: frame, screen: screen)
            setFrameOrigin(point)
        } else {
            guard
                let appState,
                let section = appState.menuBarManager.section(withName: .visible),
                let windowFrame = section.controlItem.windowFrame
            else {
                return
            }
            let margin: CGFloat = 5
            let origin = CGPoint(
                x: min(
                    windowFrame.midX - (frame.width / 2),
                    (screen.frame.maxX - frame.width) - margin
                ),
                y: (screen.visibleFrame.maxY - frame.height) - margin
            )
            setFrameOrigin(origin)
        }
    }

    @objc private func togglePinAtCurrentLocation() {
        if isPinned {
            pinnedLocation = nil
        } else if let screen {
            pinnedLocation = IceBarPinnedLocation(frame: frame, screen: screen)
        }
    }

    func show(section: MenuBarSection.Name, on screen: NSScreen) {
        guard let appState else {
            return
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
        makeKeyAndOrderFront(nil)
        currentSection = section
    }

    override func close() {
        super.close()
        contentView = nil
        currentSection = nil
    }

    override func rightMouseDown(with event: NSEvent) {
        super.rightMouseDown(with: event)

        let menu = NSMenu(title: "Ice Bar Options")

        let pinItem = NSMenuItem(
            title: "\(isPinned ? "Unpin" : "Pin") Ice Bar",
            action: #selector(togglePinAtCurrentLocation),
            keyEquivalent: ""
        )
        pinItem.target = self
        menu.addItem(pinItem)

        menu.popUp(positioning: nil, at: event.locationInWindow, in: contentView)
    }
}

// MARK: - IceBarImageCache

private class IceBarImageCache: ObservableObject {
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
        let info = item.info
        let image: CGImage? = {
            if let image = imageCache.image(for: info) {
                return image
            }
            if let image = Bridging.captureWindow(item.windowID, option: .boundsIgnoreFraming) {
                imageCache.cache(image: image, for: info)
                return image
            }
            return nil
        }()
        guard let image else {
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
                .onTapGesture {
                    closePanel()
                    itemManager.temporarilyShowItem(item)
                }
        }
    }
}

// MARK: - IceBarPinnedLocation

struct IceBarPinnedLocation: Codable {
    enum HorizontalScreenRegion: Int, Codable {
        case left = 0
        case right = 1
        case center = 3
    }

    enum VerticalScreenRegion: Int, Codable {
        case bottom = 0
        case top = 1
        case center = 3
    }

    var horizontalPercent: CGFloat
    var verticalPercent: CGFloat
    var horizontalRegion: HorizontalScreenRegion
    var verticalRegion: VerticalScreenRegion

    init(frame: CGRect, screen: NSScreen) {
        if ((screen.frame.midX - 5)...(screen.frame.midX + 5)).contains(frame.midX) {
            self.horizontalPercent = frame.midX / screen.frame.width
            self.horizontalRegion = .center
        } else if frame.midX > screen.frame.midX {
            self.horizontalPercent = frame.maxX / screen.frame.width
            self.horizontalRegion = .right
        } else {
            self.horizontalPercent = frame.minX / screen.frame.width
            self.horizontalRegion = .left
        }
        if ((screen.frame.midY - 5)...(screen.frame.midY + 5)).contains(frame.midY) {
            self.verticalPercent = frame.midY / screen.frame.height
            self.verticalRegion = .center
        } else if frame.midY > screen.frame.midY {
            self.verticalPercent = frame.maxY / screen.frame.height
            self.verticalRegion = .top
        } else {
            self.verticalPercent = frame.minY / screen.frame.height
            self.verticalRegion = .bottom
        }
    }

    func point(frame: CGRect, screen: NSScreen) -> CGPoint {
        var point = CGPoint.zero

        switch horizontalRegion {
        case .left:
            point.x = screen.frame.width * horizontalPercent
        case .right:
            point.x = (screen.frame.width * horizontalPercent) - frame.width
        case .center:
            point.x = (screen.frame.width * horizontalPercent) - (frame.width / 2)
        }

        switch verticalRegion {
        case .bottom:
            point.y = screen.frame.height * verticalPercent
        case .top:
            point.y = (screen.frame.height * verticalPercent) - frame.height
        case .center:
            point.y = (screen.frame.height * verticalPercent) - (frame.height / 2)
        }

        return point
    }
}

// MARK: - Logger

private extension Logger {
    static let iceBar = Logger(category: "IceBar")
}
