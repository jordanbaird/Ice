//
//  MenuBarSettingsPaneLayoutTab.swift
//  Ice
//

import SwiftUI

struct MenuBarSettingsPaneLayoutTab: View {
    @AppStorage(Defaults.usesColoredLayoutBars) var usesColoredLayoutBars = true
    @EnvironmentObject var menuBar: MenuBar
    @State private var visibleItems = [LayoutBarItem]()
    @State private var hiddenItems = [LayoutBarItem]()
    @State private var alwaysHiddenItems = [LayoutBarItem]()

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                headerText
                layoutViews
                Spacer()
            }
            .padding()
        }
        .scrollBounceBehavior(.basedOnSize)
        .onAppear {
            handleAppear()
        }
        .onDisappear {
            handleDisappear()
        }
        .onChange(of: menuBar.itemManager.visibleItems) { items in
            updateVisibleItems(items)
        }
        .onChange(of: menuBar.itemManager.hiddenItems) { items in
            updateHiddenItems(items)
        }
        .onChange(of: menuBar.itemManager.alwaysHiddenItems) { items in
            updateAlwaysHiddenItems(items)
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
                LayoutBar(
                    backgroundColor: menuBar.averageColor,
                    tint: menuBar.appearanceManager.tint.map { Color(cgColor: $0) },
                    layoutItems: $visibleItems
                )
                .annotation {
                    Text("Drag menu bar items to this section if you want them to always be visible.")
                }
            }

            Spacer()
                .frame(maxHeight: 25)

            Section("Hidden") {
                LayoutBar(
                    backgroundColor: menuBar.averageColor,
                    tint: menuBar.appearanceManager.tint.map { Color(cgColor: $0) },
                    layoutItems: $hiddenItems
                )
                .annotation {
                    Text("Drag menu bar items to this section if you want to hide them.")
                }
            }

            Spacer()
                .frame(maxHeight: 25)

            Section("Always Hidden") {
                LayoutBar(
                    backgroundColor: menuBar.averageColor,
                    tint: menuBar.appearanceManager.tint.map { Color(cgColor: $0) },
                    layoutItems: $alwaysHiddenItems
                )
                .annotation {
                    Text("Drag menu bar items to this section if you want them to always be hidden.")
                }
            }
        }
    }

    private func handleAppear() {
        menuBar.publishesAverageColor = usesColoredLayoutBars
        updateVisibleItems(menuBar.itemManager.visibleItems)
        updateHiddenItems(menuBar.itemManager.hiddenItems)
        updateAlwaysHiddenItems(menuBar.itemManager.alwaysHiddenItems)
    }

    private func handleDisappear() {
        menuBar.publishesAverageColor = false
    }

    private func updateVisibleItems(_ items: [MenuBarItem]) {
        let disabledItemTitles = [
            "Clock",
            "Siri",
            "Control Center",
        ]
        visibleItems = items.map { item in
            LayoutBarItem(
                image: item.image,
                size: item.window.frame.size,
                toolTip: item.title,
                isEnabled: !disabledItemTitles.contains(item.title)
            )
        }
    }

    private func updateHiddenItems(_ items: [MenuBarItem]) {
        hiddenItems = items.map { item in
            LayoutBarItem(
                image: item.image,
                size: item.window.frame.size,
                toolTip: item.title,
                isEnabled: true
            )
        }
    }

    private func updateAlwaysHiddenItems(_ items: [MenuBarItem]) {
        alwaysHiddenItems = items.map { item in
            LayoutBarItem(
                image: item.image,
                size: item.window.frame.size,
                toolTip: item.title,
                isEnabled: true
            )
        }
    }
}

#Preview {
    let menuBar = MenuBar()

    return MenuBarSettingsPaneLayoutTab()
        .fixedSize()
        .environmentObject(menuBar)
}
