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
            name: .menuBar,
            icon: .systemSymbol("menubar.rectangle")
        ),
        SettingsNavigationItem(
            name: .about,
            icon: .assetCatalog(.iceCube)
        ),
    ]

    @State private var selection = Self.items[0]

    var body: some View {
        NavigationSplitView {
            sidebar
        } detail: {
            detailView
                .frame(maxHeight: .infinity)
                .navigationTitle(selection.name.localized)
        }
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
                    Image(.iceCube)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(width: 30, height: 30)

                    Text(Constants.appName)
                        .font(.system(size: 30, weight: .medium))
                }
                .foregroundColor(.primary)
                .padding(.horizontal, 5)
                .padding(.vertical, 10)
                .padding(.bottom, 8)
            }
            .collapsible(false)
        }
        .scrollBounceBehavior(.basedOnSize)
        .removeSidebarToggle()
        .navigationSplitViewColumnWidth(
            min: 200,
            ideal: 0,
            max: 300
        )
    }

    @ViewBuilder
    private var detailView: some View {
        switch selection.name {
        case .general:
            GeneralSettingsPane()
        case .menuBar:
            MenuBarSettingsPane()
        case .about:
            AboutSettingsPane()
        }
    }

    @ViewBuilder
    private func sidebarItem(item: SettingsNavigationItem) -> some View {
        Label {
            Text(item.name.localized)
                .font(.title3)
                .padding(.leading, 6)
        } icon: {
            item.icon.view
                .padding(6)
                .foregroundStyle(Color(nsColor: .linkColor))
                .frame(width: 32, height: 32)
                .background {
                    VisualEffectView(
                        material: .sidebar,
                        isEmphasized: true
                    )
                    .brightness(0.05)
                    .clipShape(Circle())
                }
                .shadow(
                    color: .black.opacity(0.25),
                    radius: 1
                )
        }
        .padding(.leading, 8)
        .frame(height: 50)
    }
}

#Preview {
    let appState = AppState()

    return SettingsView()
        .buttonStyle(.custom)
        .environmentObject(appState)
}
