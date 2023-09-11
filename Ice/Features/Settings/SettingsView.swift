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
            name: .menuBarLayout,
            icon: .systemSymbol("menubar.rectangle")
        ),
        SettingsNavigationItem(
            name: .about,
            icon: .assetCatalog("IceCube")
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
                ForEach(Self.items) { item in
                    sidebarItem(item: item)
                }
            } header: {
                HStack {
                    Image("IceCube")
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(width: 30, height: 30)

                    Text(Constants.appName)
                        .font(.system(size: 30, weight: .medium))
                }
                .foregroundColor(.primary)
                .padding(.leading, 5)
                .padding(.bottom, 18)
            }
            .collapsible(false)
        }
        .navigationSplitViewColumnWidth(
            min: 220,
            ideal: 0,
            max: 320
        )
    }

    @ViewBuilder
    private var detailView: some View {
        switch selection.name {
        case .general:
            GeneralSettingsPane()
        case .menuBarLayout:
            MenuBarLayoutSettingsPane()
        case .about:
            AboutSettingsPane()
        }
    }

    @ViewBuilder
    private func sidebarItem(item: SettingsNavigationItem) -> some View {
        NavigationLink(value: item) {
            Label {
                Text(item.name.localized)
                    .font(.title3)
                    .padding(.leading, 6)
            } icon: {
                item.icon.view
                    .padding(6)
                    .foregroundColor(Color(nsColor: .linkColor))
                    .frame(width: 32, height: 32)
                    .background(
                        VisualEffectView(material: .sidebar, isEmphasized: true)
                            .brightness(0.05)
                            .clipShape(Circle())
                    )
                    .shadow(color: .black.opacity(0.25), radius: 1)
            }
            .padding(.leading, 8)
            .frame(height: 50)
        }
    }
}

struct SettingsView_Previews: PreviewProvider {
    @StateObject private static var statusBar = StatusBar()

    static var previews: some View {
        SettingsView()
            .buttonStyle(SettingsButtonStyle())
            .environmentObject(statusBar)
    }
}
