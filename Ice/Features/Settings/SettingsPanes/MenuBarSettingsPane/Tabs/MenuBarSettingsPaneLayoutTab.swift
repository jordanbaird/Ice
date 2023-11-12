//
//  MenuBarSettingsPaneLayoutTab.swift
//  Ice
//

import SwiftUI

struct MenuBarSettingsPaneLayoutTab: View {
    @AppStorage(Defaults.usesLayoutBarDecorations) var usesLayoutBarDecorations = true
    @EnvironmentObject var appState: AppState

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
            if let visibleSection = appState.menuBar.section(withName: .visible) {
                Section("Always Visible") {
                    LayoutBar(
                        appState: appState,
                        section: visibleSection
                    )
                    .annotation {
                        Text("Drag menu bar items to this section if you want them to always be visible.")
                    }
                }
            }

            if let hiddenSection = appState.menuBar.section(withName: .hidden) {
                Spacer()
                    .frame(maxHeight: 25)

                Section("Hidden") {
                    LayoutBar(
                        appState: appState,
                        section: hiddenSection
                    )
                    .annotation {
                        Text("Drag menu bar items to this section if you want to hide them.")
                    }
                }
            }

            if let alwaysHiddenSection = appState.menuBar.section(withName: .alwaysHidden) {
                Spacer()
                    .frame(maxHeight: 25)

                Section("Always Hidden") {
                    LayoutBar(
                        appState: appState,
                        section: alwaysHiddenSection
                    )
                    .annotation {
                        Text("Drag menu bar items to this section if you want them to always be hidden.")
                    }
                }
            }
        }
    }

    private func handleAppear() {
        appState.menuBar.publishesAverageColor = usesLayoutBarDecorations
        appState.itemManager.startObservingMenuBarItems()
    }

    private func handleDisappear() {
        appState.menuBar.publishesAverageColor = false
        appState.itemManager.stopObservingMenuBarItems()
    }
}

#Preview {
    MenuBarSettingsPaneLayoutTab()
        .fixedSize()
        .environmentObject(AppState.shared)
}
