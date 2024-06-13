//
//  SecondaryBar.swift
//  Ice
//

import Bridging
import Combine
import SwiftUI

// MARK: - SecondaryBarPanel

class SecondaryBarPanel: NSPanel {
    private weak var appState: AppState?

    private(set) var currentSection: MenuBarSection.Name?

    private var cancellables = Set<AnyCancellable>()

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
        self.isMovable = false
        self.animationBehavior = .none
        self.level = .mainMenu
        self.collectionBehavior = [.fullScreenNone, .ignoresCycle, .moveToActiveSpace]
        configureCancellables()
    }

    private func configureCancellables() {
        var c = Set<AnyCancellable>()

        // close the panel when the active space changes
        NSWorkspace.shared.notificationCenter
            .publisher(for: NSWorkspace.activeSpaceDidChangeNotification)
            .debounce(for: 0.1, scheduler: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.close()
            }
            .store(in: &c)

        publisher(for: \.frame)
            .sink { [weak self] frame in
                guard
                    let self,
                    let screen
                else {
                    return
                }
                updateOrigin(for: screen, frame: frame)
            }
            .store(in: &c)

        cancellables = c
    }

    private func updateOrigin(for screen: NSScreen, frame: CGRect) {
        let origin = CGPoint(
            x: (screen.visibleFrame.maxX - frame.width) - 5,
            y: (screen.visibleFrame.maxY - frame.height) - 5
        )
        setFrameOrigin(origin)
    }

    func show(section: MenuBarSection.Name, on screen: NSScreen) {
        guard let appState else {
            return
        }
        contentView = SecondaryBarHostingView(appState: appState, section: section) { [weak self] in
            self?.close()
        }
        makeKeyAndOrderFront(nil)
        currentSection = section
    }

    override func close() {
        super.close()
        contentView = nil
        currentSection = nil
    }
}

// MARK: - SecondaryBarHostingView

private class SecondaryBarHostingView: NSHostingView<AnyView> {
    override var safeAreaInsets: NSEdgeInsets {
        NSEdgeInsets()
    }

    init(appState: AppState, section: MenuBarSection.Name, closePanel: @escaping () -> Void) {
        super.init(
            rootView: SecondaryBarContentView(section: section, closePanel: closePanel)
                .environmentObject(appState)
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
}

// MARK: - SecondaryBarContentView

private struct SecondaryBarContentView: View {
    @EnvironmentObject var appState: AppState

    let section: MenuBarSection.Name
    let closePanel: () -> Void

    private var items: [MenuBarItem] {
        appState.itemManager.cachedMenuBarItems[section, default: []]
    }

    var body: some View {
        HStack(spacing: 0) {
            ForEach(items, id: \.windowID) { item in
                SecondaryBarItemView(item: item, closePanel: closePanel)
            }
        }
        .padding(5)
        .layoutBarStyle(menuBarManager: appState.menuBarManager, cornerRadius: 0)
        .fixedSize()
    }
}

// MARK: - SecondaryBarItemView

private struct SecondaryBarItemView: View {
    @EnvironmentObject var appState: AppState

    let item: MenuBarItem
    let closePanel: () -> Void

    private var size: CGSize {
        CGSize(width: item.frame.width, height: item.frame.height)
    }

    var body: some View {
        if let image = Bridging.captureWindow(item.windowID, option: .boundsIgnoreFraming) {
            Image(nsImage: NSImage(cgImage: image, size: size))
                .onTapGesture {
                    closePanel()
                    appState.itemManager.temporarilyShowItem(item)
                }
        }
    }
}
