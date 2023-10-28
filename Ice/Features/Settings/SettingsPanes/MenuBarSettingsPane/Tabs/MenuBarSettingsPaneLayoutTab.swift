//
//  MenuBarSettingsPaneLayoutTab.swift
//  Ice
//

import SwiftUI

struct MenuBarSettingsPaneLayoutTab: View {
    @AppStorage(Defaults.usesColoredLayoutBars) var usesColoredLayoutBars = true
    @EnvironmentObject var appState: AppState
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
        .onChange(of: appState.itemManager.visibleItems) { items in
            updateVisibleItems(items)
        }
        .onChange(of: appState.itemManager.hiddenItems) { items in
            updateHiddenItems(items)
        }
        .onChange(of: appState.itemManager.alwaysHiddenItems) { items in
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
                    menuBar: appState.menuBar,
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
                    menuBar: appState.menuBar,
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
                    menuBar: appState.menuBar,
                    layoutItems: $alwaysHiddenItems
                )
                .annotation {
                    Text("Drag menu bar items to this section if you want them to always be hidden.")
                }
            }
        }
    }

    private func handleAppear() {
        appState.menuBar.publishesAverageColor = usesColoredLayoutBars
        updateVisibleItems(appState.itemManager.visibleItems)
        updateHiddenItems(appState.itemManager.hiddenItems)
        updateAlwaysHiddenItems(appState.itemManager.alwaysHiddenItems)
    }

    private func handleDisappear() {
        appState.menuBar.publishesAverageColor = false
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
    let appState = AppState()

    return MenuBarSettingsPaneLayoutTab()
        .fixedSize()
        .environmentObject(appState)
}
