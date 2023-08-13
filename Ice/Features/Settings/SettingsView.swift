//
//  SettingsView.swift
//  Ice
//

import SwiftUI

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
                SettingsSidebarItem(item: item)
            }
            .navigationSplitViewColumnWidth(225)
            .padding(.top, 5)
        } detail: {
            Text(selection.name.localized).font(.title)
        }
    }
}

struct SettingsSidebarItem: View {
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
                .background(
                    Circle().fill(item.secondaryColor)
                )
                .shadow(color: .black.opacity(0.25), radius: 1)
            }
            .padding(.leading, 6)
            .frame(height: 50)
        }
    }
}

struct SettingsView_Previews: PreviewProvider {
    static var previews: some View {
        SettingsView()
    }
}
