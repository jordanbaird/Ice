//
//  IceBar.swift
//  Ice
//

import Bridging
import Combine
import SwiftUI

// MARK: - IceBarPanel

class IceBarPanel: NSPanel {
    private weak var appState: AppState?

    private(set) var currentSection: MenuBarSection.Name?

    private var cancellables = Set<AnyCancellable>()

    init(appState: AppState) {
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

        // close the panel when the active space changes, or when the
        // screen parameters change
        Publishers.Merge(
            NSWorkspace.shared.notificationCenter.publisher(for: NSWorkspace.activeSpaceDidChangeNotification),
            NotificationCenter.default.publisher(for: NSApplication.didChangeScreenParametersNotification)
        )
        .sink { [weak self] _ in
            self?.close()
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

        // important that we set the current section before updating the cache
        currentSection = section
        await appState.imageCache.updateCache()

        contentView = IceBarHostingView(
            appState: appState,
            imageCache: appState.imageCache,
            section: section,
            screen: screen
        ) { [weak self] in
            self?.close()
        }

        updateOrigin(for: screen)
        orderFrontRegardless()
    }

    override func close() {
        super.close()
        contentView = nil
        currentSection = nil
    }
}

// MARK: - IceBarHostingView

private class IceBarHostingView: NSHostingView<AnyView> {
    override var safeAreaInsets: NSEdgeInsets {
        NSEdgeInsets()
    }

    init(
        appState: AppState,
        imageCache: MenuBarItemImageCache,
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
    @EnvironmentObject var imageCache: MenuBarItemImageCache

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
        if imageCache.isEmpty(for: section) {
            Text("Unable to display menu bar items. Try switching spaces.")
                .foregroundStyle(menuBarManager.averageColor?.brightness ?? 0 > 0.67 ? .black : .white)
                .padding(3)
        } else {
            HStack(spacing: 0) {
                ForEach(items, id: \.windowID) { item in
                    IceBarItemView(item: item, screen: screen, closePanel: closePanel)
                }
            }
        }
    }
}

// MARK: - IceBarItemView

private struct IceBarItemView: View {
    @EnvironmentObject var itemManager: MenuBarItemManager
    @EnvironmentObject var imageCache: MenuBarItemImageCache

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
