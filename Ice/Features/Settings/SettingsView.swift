//
//  SettingsView.swift
//  Ice
//

import SwiftUI

// MARK: - SettingsView

struct SettingsView: View {
    private static let items: [SettingsItem] = [
        SettingsItem(
            name: .general,
            icon: .systemSymbol("gearshape")
        ),
        SettingsItem(
            name: .menuBarLayout,
            icon: .systemSymbol("menubar.rectangle")
        ),
        SettingsItem(
            name: .about,
            icon: .assetCatalog("IceCube")
        ),
    ]

    @State private var selection = Self.items[0]

    var body: some View {
        NavigationSplitView {
            List(Self.items, selection: $selection) { item in
                SettingsSidebarView(item: item)
            }
            .navigationSplitViewColumnWidth(225)
            .padding(.top, 5)
        } detail: {
            SettingsDetailView(item: selection)
        }
    }
}

// MARK: - SettingsSidebarView

struct SettingsSidebarView: View {
    let item: SettingsItem

    var body: some View {
        NavigationLink(value: item) {
            Label {
                Text(item.name.localized)
                    .font(.title3)
                    .padding(.leading, 6)
            } icon: {
                Group {
                    switch item.icon {
                    case .systemSymbol(let name):
                        Image(systemName: name)
                            .resizable()
                            .aspectRatio(contentMode: .fit)
                    case .assetCatalog(let name):
                        Image(name)
                            .resizable()
                            .aspectRatio(contentMode: .fit)
                    }
                }
                .padding(6)
                .foregroundColor(item.primaryColor)
                .frame(width: 32, height: 32)
                .background(item.secondaryColor, in: Circle())
                .shadow(color: .black.opacity(0.25), radius: 1)
            }
            .padding(.leading, 8)
            .frame(height: 50)
        }
    }
}

// MARK: - SettingsDetailView

struct SettingsDetailView: View {
    let item: SettingsItem

    var body: some View {
        switch item.name {
        case .general:
            GeneralSettingsView()
        case .menuBarLayout:
            Text(item.name.localized).font(.title)
        case .about:
            Text(item.name.localized).font(.title)
        }
    }
}

// MARK: - Previews

struct SettingsView_Previews: PreviewProvider {
    static var previews: some View {
        SettingsView()
    }
}
