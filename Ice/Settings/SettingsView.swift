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
            case .small: 240
            case .medium: 260
            case .large: 280
            @unknown default: 260
            }
        } else {
            switch sidebarRowSize {
            case .small: 230
            case .medium: 255
            case .large: 270
            @unknown default: 255
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
                HStack(spacing: 8) {
                    if let appIcon = NSImage(named: NSImage.applicationIconName) {
                        Image(nsImage: appIcon)
                            .resizable()
                            .scaledToFit()
                            .frame(width: sidebarFontSize * 3, height: sidebarFontSize * 3)
                    }
                    Text("Ice")
                        .font(.system(size: sidebarFontSize * 2.2, weight: .semibold))
                        .foregroundStyle(sidebarTextStyle)
                }
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
        HStack(spacing: 8) {
            SidebarIconTile(
                icon: identifier.iconResource,
                color: tileColor(for: identifier),
                size: sidebarItemHeight - 8
            )
            Text(identifier.localized)
                .font(.system(size: sidebarFontSize))
                .foregroundStyle(sidebarTextStyle)
        }
        .padding(.leading, sidebarPadding)
        .frame(height: sidebarItemHeight)
        .tag(identifier)
    }

    private func tileColor(for identifier: SettingsNavigationIdentifier) -> Color {
        switch identifier {
        case .general: .gray
        case .menuBarLayout: .blue
        case .menuBarAppearance: .pink
        case .hotkeys: .orange
        case .advanced: .indigo
        case .help: .green
        case .about: .cyan
        }
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
        case .help:
            HelpSettingsPane()
        case .about:
            AboutSettingsPane(updatesManager: appState.updatesManager)
        }
    }
}

/// A colored, rounded icon tile in the style of the System Settings sidebar.
private struct SidebarIconTile: View {
    let icon: IconResource
    let color: Color
    let size: CGFloat

    var body: some View {
        RoundedRectangle(cornerRadius: size * 0.28, style: .continuous)
            .fill(color.gradient)
            .frame(width: size, height: size)
            .overlay {
                icon.image
                    .renderingMode(.template)
                    .resizable()
                    .scaledToFit()
                    .foregroundStyle(.white)
                    .padding(size * 0.2)
            }
            .shadow(color: .black.opacity(0.15), radius: 0.5, y: 0.5)
    }
}
