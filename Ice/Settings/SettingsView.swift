//
//  SettingsView.swift
//  Ice
//

import SwiftUI

struct SettingsView: View {
    @EnvironmentObject var appState: AppState
    @ObservedObject var navigationState: AppNavigationState
    @Environment(\.appearsActive) private var appearsActive
    @Environment(\.sidebarRowSize) private var sidebarRowSize

    private let sidebarPadding: CGFloat = 3

    private var sidebarWidth: CGFloat {
        if #available(macOS 26.0, *) {
            switch sidebarRowSize {
            case .small: 200
            case .medium: 220
            case .large: 240
            @unknown default: 220
            }
        } else {
            switch sidebarRowSize {
            case .small: 190
            case .medium: 215
            case .large: 230
            @unknown default: 215
            }
        }
    }

    private var sidebarItemHeight: CGFloat {
        switch sidebarRowSize {
        case .small: 26
        case .medium: 32
        case .large: 34
        @unknown default: 32
        }
    }

    private var sidebarFontSize: CGFloat {
        switch sidebarRowSize {
        case .small: 13
        case .medium: 15
        case .large: 16
        @unknown default: 15
        }
    }

    private var sidebarTextStyle: some ShapeStyle {
        appearsActive ? .primary : .secondary
    }

    private var navigationTitle: LocalizedStringKey {
        navigationState.settingsNavigationIdentifier.localized
    }

    var body: some View {
        NavigationSplitView {
            sidebar
        } detail: {
            detailView
        }
        .navigationTitle(navigationTitle)
    }

    @ViewBuilder
    private var sidebar: some View {
        List(selection: $navigationState.settingsNavigationIdentifier) {
            Section {
                ForEach(SettingsNavigationIdentifier.allCases) { identifier in
                    sidebarItem(for: identifier)
                }
            } header: {
                Text("Ice")
                    .font(.system(size: sidebarFontSize * 2.67, weight: .medium))
                    .foregroundStyle(sidebarTextStyle)
                    .padding(.leading, sidebarPadding)
                    .padding(.bottom, sidebarFontSize)
            }
            .collapsible(false)
        }
        .scrollDisabled(true)
        .toolbar(removing: .sidebarToggle)
        .toolbar {
            sidebarToolbarSpacer
        }
        .navigationSplitViewColumnWidth(sidebarWidth)
    }

    @ViewBuilder
    private func sidebarItem(for identifier: SettingsNavigationIdentifier) -> some View {
        Label {
            Text(identifier.localized)
                .font(.system(size: sidebarFontSize))
                .foregroundStyle(sidebarTextStyle)
        } icon: {
            identifier.iconResource.view
                .foregroundStyle(sidebarTextStyle)
                .padding(sidebarPadding)
        }
        .frame(height: sidebarItemHeight)
        .tag(identifier)
    }

    @ToolbarContentBuilder
    private var sidebarToolbarSpacer: some ToolbarContent {
        if #available(macOS 26.0, *) {
            ToolbarSpacer(.flexible)
        } else {
            ToolbarItem {
                Spacer(minLength: 0)
            }
        }
    }

    @ViewBuilder
    private var detailView: some View {
        if #available(macOS 26.0, *) {
            settingsPane
                .scrollEdgeEffectStyle(.hard, for: .top)
        } else {
            settingsPane
        }
    }

    @ViewBuilder
    private var settingsPane: some View {
        switch navigationState.settingsNavigationIdentifier {
        case .general:
            GeneralSettingsPane(settings: appState.settings.general)
        case .menuBarLayout:
            MenuBarLayoutSettingsPane(itemManager: appState.itemManager)
        case .menuBarAppearance:
            MenuBarAppearanceSettingsPane(appearanceManager: appState.appearanceManager)
        case .hotkeys:
            HotkeysSettingsPane(settings: appState.settings.hotkeys)
        case .advanced:
            AdvancedSettingsPane(settings: appState.settings.advanced)
        case .about:
            AboutSettingsPane(updatesManager: appState.updatesManager)
        }
    }
}
