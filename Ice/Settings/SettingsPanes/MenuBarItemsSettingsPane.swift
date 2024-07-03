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
                Text("Tip: you can also arrange items by ⌘ (Command) + dragging them in the menu bar.")
            }
    }

    @ViewBuilder
    private var layoutBars: some View {
        VStack(spacing: 25) {
            layoutBar(
                for: .visible,
                annotation: "Drag menu bar items to this section if you want them to always be visible."
            )
            layoutBar(
                for: .hidden,
                annotation: "Drag menu bar items to this section if you want them to be hidden."
            )
            layoutBar(
                for: .alwaysHidden,
                annotation: "Drag menu bar items to this section if you want them to always be hidden."
            )
        }
    }

    @ViewBuilder
    private var cannotArrange: some View {
        Text("Ice cannot arrange the items of automatically hidden menu bars.")
            .font(.title3)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
    }

    @ViewBuilder
    private func layoutBar(
        for section: MenuBarSection.Name,
        annotation: LocalizedStringKey
    ) -> some View {
        if
            let section = appState.menuBarManager.section(withName: section),
            section.isEnabled
        {
            VStack(alignment: .leading) {
                Section {
                    LayoutBar(section: section)
                } header: {
                    Text(section.name.menuString)
                } footer: {
                    Text(annotation)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }
}
