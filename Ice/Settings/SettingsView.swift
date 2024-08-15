//
//  SettingsView.swift
//  Ice
//

import SwiftUI

struct SettingsView: View {
    @EnvironmentObject var navigationState: AppNavigationState

    var body: some View {
        NavigationSplitView {
            sidebar
        } detail: {
            detailView
        }
        .navigationTitle(navigationState.settingsNavigationIdentifier.localized)
    }

    @ViewBuilder
    private var sidebar: some View {
        List(selection: $navigationState.settingsNavigationIdentifier) {
            Section {
                ForEach(SettingsNavigationIdentifier.allCases, id: \.self) { identifier in
                    sidebarItem(for: identifier)
                }
            } header: {
                HStack {
                    Image(.iceCubeStroke)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(width: 30, height: 30)

                    Text("Ice")
                        .font(.system(size: 30, weight: .medium))
                }
                .foregroundStyle(.primary)
                .padding(.vertical, 8)
            }
            .collapsible(false)
        }
        .removeSidebarToggle()
        .navigationSplitViewColumnWidth(210)
    }

    @ViewBuilder
    private var detailView: some View {
        switch navigationState.settingsNavigationIdentifier {
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
    private func sidebarItem(for identifier: SettingsNavigationIdentifier) -> some View {
        Label {
            Text(identifier.localized)
                .font(.title3)
                .padding(.leading, 2)
        } icon: {
            icon(for: identifier).view
                .foregroundStyle(.primary)
        }
        .frame(height: 32)
    }

    private func icon(for identifier: SettingsNavigationIdentifier) -> IconResource {
        switch identifier {
        case .general: .systemSymbol("gearshape")
        case .menuBarItems: .systemSymbol("menubar.rectangle")
        case .menuBarAppearance: .systemSymbol("paintpalette")
        case .hotkeys: .systemSymbol("keyboard")
        case .advanced: .systemSymbol("gearshape.2")
        case .updates: .systemSymbol("arrow.triangle.2.circlepath.circle")
        case .about: .assetCatalog(.iceCubeStroke)
        }
    }
}
