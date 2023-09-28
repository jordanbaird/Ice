//
//  MenuBarLayoutSettingsPane.swift
//  Ice
//

import SwiftUI

struct MenuBarLayoutSettingsPane: View {
    @EnvironmentObject var styleReader: LayoutBarStyleReader
    @EnvironmentObject var menuBar: MenuBar
    @EnvironmentObject var itemManager: MenuBarItemManager

    @AppStorage(Defaults.usesTintedLayoutBars)
    var usesTintedLayoutBars = true

    @State private var allItems = [LayoutBarItem]()

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
        .onChange(of: itemManager.items) { items in
            updateAllItems(items)
        }
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
                LayoutBar(layoutItems: $allItems)
                    .annotation {
                        Text("Drag menu bar items to this section if you want them to always be visible.")
                    }
            }
            Spacer()
                .frame(maxHeight: 25)
            Section("Hidden") {
                LayoutBar(layoutItems: .constant([]))
                    .annotation {
                        Text("Drag menu bar items to this section if you want to hide them.")
                    }
            }
            Spacer()
                .frame(maxHeight: 25)
            Section("Always Hidden") {
                LayoutBar(layoutItems: .constant([]))
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
        updateAllItems(itemManager.items)
    }

    private func handleDisappear() {
        styleReader.deactivate()
        itemManager.deactivate()
    }

    @MainActor
    private func updateAllItems(_ items: [MenuBarItem]) {
        allItems = items.compactMap { item in
            WindowCaptureManager.captureImage(window: item.window).map { image in
                LayoutBarItem(
                    image: image,
                    size: item.window.frame.size,
                    toolTip: item.title,
                    isEnabled: !["Clock", "Siri", "Control Center"].contains(item.title)
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
