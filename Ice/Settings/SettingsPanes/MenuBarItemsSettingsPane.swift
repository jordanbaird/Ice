//
//  MenuBarItemsSettingsPane.swift
//  Ice
//

import SwiftUI

struct MenuBarItemsSettingsPane: View {
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
            if let visibleSection = appState.menuBarManager.section(withName: .visible) {
                Section(visibleSection.name.menuString) {
                    LayoutBar(section: visibleSection)
                        .annotation {
                            Text("Drag menu bar items to this section if you want them to always be visible.")
                        }
                }
            }

            if let hiddenSection = appState.menuBarManager.section(withName: .hidden) {
                Spacer()
                    .frame(maxHeight: 25)

                Section(hiddenSection.name.menuString) {
                    LayoutBar(section: hiddenSection)
                        .annotation {
                            Text("Drag menu bar items to this section if you want to hide them.")
                        }
                }
            }

            if let alwaysHiddenSection = appState.menuBarManager.section(withName: .alwaysHidden) {
                Spacer()
                    .frame(maxHeight: 25)

                Section(alwaysHiddenSection.name.menuString) {
                    LayoutBar(section: alwaysHiddenSection)
                        .annotation {
                            Text("Drag menu bar items to this section if you want them to always be hidden.")
                        }
                }
            }
        }
    }
}
