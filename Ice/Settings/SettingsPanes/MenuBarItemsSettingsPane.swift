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
            IceForm(alignment: .leading, spacing: 20) {
                header
                layoutBars
            }
        }
    }

    @ViewBuilder
    private var header: some View {
        Text("Drag to arrange your menu bar items")
            .font(.title2)

        IceSection {
            AnnotationView(
                alignment: .center,
                font: .callout.bold()
            ) {
                Label {
                    Text("Tip: you can also arrange menu bar items by ⌘ + dragging them in the menu bar")
                } icon: {
                    Image(systemName: "lightbulb")
                }
            }
        }
    }

    @ViewBuilder
    private var layoutBars: some View {
        VStack(spacing: 25) {
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
                Text(section.name.menuString + " Section")
                    .font(.system(size: 14))

                LayoutBar(section: section)
                    .environmentObject(appState.imageCache)
            }
        }
    }
}
