//
//  MenuBarLayoutSettingsPane.swift
//  Ice
//

import SwiftUI

struct MenuBarLayoutSettingsPane: View {
    @StateObject private var styleReader: LayoutBarStyleReader

    @EnvironmentObject var menuBar: MenuBar
    @EnvironmentObject var itemManager: MenuBarItemManager

    @AppStorage(Defaults.usesTintedLayoutBars) var usesTintedLayoutBars = true

    @State private var alwaysVisibleItems = [LayoutBarItem]()
    @State private var hiddenItems = [LayoutBarItem]()
    @State private var alwaysHiddenItems = [LayoutBarItem]()

    init() {
        let styleReader = LayoutBarStyleReader(windowList: .shared)
        self._styleReader = StateObject(wrappedValue: styleReader)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                headerText
                layoutViews
                Spacer()
            }
        }
        .scrollBounceBehavior(.basedOnSize)
        .padding()
        .onAppear {
            handleAppear()
        }
        .onDisappear {
            handleDisappear()
        }
        .onReceive(itemManager.$alwaysVisibleItems) { items in
            updateAlwaysVisibleItems(items)
        }
        .onReceive(itemManager.$hiddenItems) { items in
            updateHiddenItems(items)
        }
        .onReceive(itemManager.$alwaysHiddenItems) { items in
            updateAlwaysHiddenItems(items)
        }
        .environmentObject(styleReader)
    }

    @ViewBuilder
    private var headerText: some View {
        Text("Drag to arrange your menu bar items")
            .font(.title2)
            .annotation {
                Text("Tip: you can also arrange items by ⌘ (Command) + dragging them in the menu bar.")
            }
    }

    @ViewBuilder
    private var layoutViews: some View {
        Form {
            Section("Always Visible") {
                LayoutBar(layoutItems: $alwaysVisibleItems)
                    .annotation {
                        Text("Drag menu bar items to this section if you want them to always be visible.")
                    }
            }

            Spacer()
                .frame(maxHeight: 25)

            Section("Hidden") {
                LayoutBar(layoutItems: $hiddenItems)
                    .annotation {
                        Text("Drag menu bar items to this section if you want to hide them.")
                    }
            }

            Spacer()
                .frame(maxHeight: 25)

            Section("Always Hidden") {
                LayoutBar(layoutItems: $alwaysHiddenItems)
                    .annotation {
                        Text("Drag menu bar items to this section if you want them to always be hidden.")
                    }
            }
        }
    }

    private func handleAppear() {
        if usesTintedLayoutBars {
            styleReader.activate()
        } else {
            styleReader.deactivate()
        }
        itemManager.activate()
    }

    private func handleDisappear() {
        styleReader.deactivate()
        itemManager.deactivate()
    }

    private func updateAlwaysVisibleItems(_ items: [MenuBarItem]) {
        let disabledItemTitles = [
            "Clock",
            "Siri",
            "Control Center",
        ]

        alwaysVisibleItems = items.compactMap { item in
            WindowCaptureManager.captureImage(window: item.window).map { image in
                LayoutBarItem(
                    image: image,
                    size: item.window.frame.size,
                    toolTip: item.title,
                    isEnabled: !disabledItemTitles.contains(item.title)
                )
            }
        }
    }

    private func updateHiddenItems(_ items: [MenuBarItem]) {
        hiddenItems = items.compactMap { item in
            WindowCaptureManager.captureImage(window: item.window).map { image in
                LayoutBarItem(
                    image: image,
                    size: item.window.frame.size,
                    toolTip: item.title,
                    isEnabled: true
                )
            }
        }
    }

    private func updateAlwaysHiddenItems(_ items: [MenuBarItem]) {
        alwaysHiddenItems = items.compactMap { item in
            WindowCaptureManager.captureImage(window: item.window).map { image in
                LayoutBarItem(
                    image: image,
                    size: item.window.frame.size,
                    toolTip: item.title,
                    isEnabled: true
                )
            }
        }
    }
}

#Preview {
    let styleReader = LayoutBarStyleReader(windowList: .shared)
    let menuBar = MenuBar()

    return MenuBarLayoutSettingsPane()
        .fixedSize()
        .environmentObject(styleReader)
        .environmentObject(menuBar)
        .environmentObject(menuBar.itemManager)
}
