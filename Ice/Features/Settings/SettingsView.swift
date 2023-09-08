//
//  SettingsView.swift
//  Ice
//

import Combine
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

    @Environment(\.colorScheme)
    private var colorScheme: ColorScheme

    @State private var window: NSWindow?
    @State private var title = ""
    @State private var isKeyWindow = false
    @State private var selection = Self.items[0]

    private var keyWindowPublisher: AnyPublisher<Bool, Never> {
        let nc = NotificationCenter.default
        let didBecomeKey = NSWindow.didBecomeKeyNotification
        let didResignKey = NSWindow.didResignKeyNotification
        return Publishers.Merge(
            nc.publisher(for: didBecomeKey),
            nc.publisher(for: didResignKey)
        )
        .map { [weak window] notif in
            guard notif.object as? NSWindow === window else {
                return false
            }
            return notif.name == didBecomeKey
        }
        .eraseToAnyPublisher()
    }

    var body: some View {
        NavigationSplitView {
            sidebar
                .safeAreaInset(edge: .top, spacing: 0) { topPadding }
                .edgesIgnoringSafeArea(.top)
        } detail: {
            detailView
                .frame(maxHeight: .infinity)
                .safeAreaInset(edge: .top, spacing: 0) { titlebar }
                .edgesIgnoringSafeArea(.top)
                .navigationTitle(selection.name.localized)
        }
        .readWindow(window: $window)
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
                        .frame(width: 32, height: 32)

                    Text(Constants.appName)
                        .font(.system(size: 32, weight: .medium))
                }
                .foregroundColor(.primary)
                .padding(.horizontal)
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
    private var topPadding: some View {
        Color.clear
            .frame(height: 50)
    }

    @ViewBuilder
    private var titlebar: some View {
        if let window {
            topPadding
                .overlay {
                    VisualEffectView(
                        material: .titlebar,
                        blendingMode: .withinWindow
                    )
                    .overlay(alignment: .leading) {
                        Text(title)
                            .font(.system(size: 15, weight: .bold))
                            .foregroundColor(isKeyWindow ? .primary : .secondary)
                            .padding()
                    }
                    .safeAreaInset(edge: .bottom, spacing: 0) {
                        Color(white: colorScheme == .dark ? 0 : 0.7)
                            .frame(height: 1)
                    }
                    .edgesIgnoringSafeArea(.top)
                    .onReceive(window.publisher(for: \.title)) { title in
                        self.title = title
                    }
                    .onReceive(keyWindowPublisher) { isKeyWindow in
                        self.isKeyWindow = isKeyWindow
                    }
                }
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
