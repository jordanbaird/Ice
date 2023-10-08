//
//  MenuBarLayoutSettingsPane.swift
//  Ice
//

import SwiftUI

struct MenuBarLayoutSettingsPane: View {
    @EnvironmentObject var menuBar: MenuBar

    @AppStorage(Defaults.usesTintedLayoutBars) var usesTintedLayoutBars = true

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
        }
        .scrollBounceBehavior(.basedOnSize)
        .padding()
        .onAppear {
            handleAppear()
        }
        .onDisappear {
            handleDisappear()
        }
        .onReceive(menuBar.itemManager.$visibleItems) { items in
            updateAlwaysVisibleItems(items)
        }
        .onReceive(menuBar.itemManager.$hiddenItems) { items in
            updateHiddenItems(items)
        }
        .onReceive(menuBar.itemManager.$alwaysHiddenItems) { items in
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
                    backgroundColor: menuBar.colorReader.color,
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
                    backgroundColor: menuBar.colorReader.color,
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
                    backgroundColor: menuBar.colorReader.color,
                    layoutItems: $alwaysHiddenItems
                )
                .annotation {
                    Text("Drag menu bar items to this section if you want them to always be hidden.")
                }
            }
        }
    }

    private func handleAppear() {
        if usesTintedLayoutBars {
            menuBar.colorReader.activate()
        } else {
            menuBar.colorReader.deactivate()
        }
    }

    private func handleDisappear() {
        menuBar.colorReader.deactivate()
    }

    private func updateAlwaysVisibleItems(_ items: [MenuBarItem]) {
        let disabledItemTitles = [
            "Clock",
            "Siri",
            "Control Center",
        ]

        visibleItems = items.compactMap { item in
            WindowCaptureManager
                .captureImage(
                    windows: [item.window],
                    options: .ignoreFraming
                )
                .map { image in
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
            WindowCaptureManager
                .captureImage(
                    windows: [item.window],
                    options: .ignoreFraming
                )
                .map { image in
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
            WindowCaptureManager
                .captureImage(
                    windows: [item.window],
                    options: .ignoreFraming
                )
                .map { image in
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
    let menuBar = MenuBar()

    return MenuBarLayoutSettingsPane()
        .fixedSize()
        .environmentObject(menuBar)
}
