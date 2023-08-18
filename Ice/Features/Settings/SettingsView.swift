//
//  SettingsView.swift
//  Ice
//

import SwiftUI

// MARK: - SettingsView

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
    let item: SettingsNavigationItem

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
    let item: SettingsNavigationItem

    var body: some View {
        switch item.name {
        case .general:
            GeneralSettingsPane()
        case .menuBarLayout:
            Text(item.name.localized).font(.title)
        case .about:
            Text(item.name.localized).font(.title)
        }
    }
}

// MARK: - Previews

struct SettingsView_Previews: PreviewProvider {
    @StateObject private static var statusBar = StatusBar()

    static var previews: some View {
        SettingsView()
            .buttonStyle(SettingsButtonStyle())
            .toggleStyle(SettingsToggleStyle())
            .environmentObject(statusBar)
    }
}
