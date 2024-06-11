//
//  SettingsView.swift
//  Ice
//

import SwiftUI

struct SettingsView: View {
    private static let items: [SettingsNavigationItem] = [
        SettingsNavigationItem(
            name: .general,
            icon: .systemSymbol("gearshape")
        ),
        SettingsNavigationItem(
            name: .menuBarItems,
            icon: .systemSymbol("menubar.rectangle")
        ),
        SettingsNavigationItem(
            name: .menuBarAppearance,
            icon: .systemSymbol("paintpalette")
        ),
        SettingsNavigationItem(
            name: .hotkeys,
            icon: .systemSymbol("keyboard")
        ),
        SettingsNavigationItem(
            name: .advanced,
            icon: .systemSymbol("gearshape.2")
        ),
        SettingsNavigationItem(
            name: .updates,
            icon: .systemSymbol("arrow.triangle.2.circlepath.circle")
        ),
        SettingsNavigationItem(
            name: .about,
            icon: .assetCatalog(.iceCubeStroke)
        ),
    ]

    @State private var selection = Self.items[0]

    var body: some View {
        NavigationSplitView {
            sidebar
        } detail: {
            detailView
        }
        .navigationTitle(selection.name.localized)
    }

    @ViewBuilder
    private var sidebar: some View {
        List(selection: $selection) {
            Section {
                ForEach(Self.items, id: \.self) { item in
                    sidebarItem(item: item)
                }
            } header: {
                HStack {
                    Image(.iceCubeStroke)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(width: 28, height: 28)

                    Text("Ice")
                        .font(.system(size: 28, weight: .medium))
                }
                .foregroundStyle(.primary)
                .padding(.bottom, 8)
            }
            .collapsible(false)
        }
        .removeSidebarToggle()
        .navigationSplitViewColumnWidth(210)
    }

    @ViewBuilder
    private var detailView: some View {
        switch selection.name {
        case .general:
            GeneralSettingsPane()
        case .menuBarItems:
            MenuBarItemsSettingsPane()
        case .menuBarAppearance:
            MenuBarAppearanceSettingsPane()
        case .hotkeys:
            HotkeysSettingsPane()
        case .advanced:
            AdvancedSettingsPane()
        case .updates:
            UpdatesSettingsPane()
        case .about:
            AboutSettingsPane()
        }
    }

    @ViewBuilder
    private func sidebarItem(item: SettingsNavigationItem) -> some View {
        Label {
            Text(item.name.localized)
                .font(.title3)
                .padding(.leading, 2)
        } icon: {
            item.icon.view
                .foregroundStyle(.primary)
        }
        .frame(height: 30)
    }
}

#Preview {
    SettingsView()
        .environmentObject(AppState())
}
