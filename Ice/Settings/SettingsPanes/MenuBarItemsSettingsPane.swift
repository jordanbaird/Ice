//
//  MenuBarItemsSettingsPane.swift
//  Ice
//

import SwiftUI

struct MenuBarItemsSettingsPane: View {
    @EnvironmentObject var appState: AppState

    var body: some View {
        if appState.menuBarManager.isMenuBarHiddenBySystemUserDefaults {
            cannotArrange
        } else {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    headerText
                    layoutBars
                    Spacer()
                }
                .padding()
            }
            .scrollBounceBehavior(.basedOnSize)
        }
    }

    @ViewBuilder
    private var headerText: some View {
        Text("Drag to arrange your menu bar items")
            .font(.title2)
            .annotation {
                Text("Tip: you can also arrange menu bar items by ⌘ + dragging them in the menu bar")
            }
    }

    @ViewBuilder
    private var layoutBars: some View {
        VStack(spacing: 10) {
            ForEach(MenuBarSection.Name.allCases, id: \.self) { section in
                layoutBar(for: section)
            }
        }
    }

    @ViewBuilder
    private var cannotArrange: some View {
        Text("Ice cannot arrange menu bar items in automatically hidden menu bars")
            .font(.title3)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
    }

    @ViewBuilder
    private func layoutBar(for section: MenuBarSection.Name) -> some View {
        if
            let section = appState.menuBarManager.section(withName: section),
            section.isEnabled
        {
            VStack(alignment: .leading, spacing: 2) {
                Text(section.name.menuString)
                    .font(.system(size: 15))
                    .padding(.leading, 5)
                LayoutBar(section: section)
                    .environmentObject(appState.imageCache)
            }
        }
    }
}
