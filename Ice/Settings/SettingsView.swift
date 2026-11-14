//
//  SettingsView.swift
//  Ice
//

import SwiftUI

struct SettingsView: View {
    @EnvironmentObject var navigationState: AppNavigationState
    @Environment(\.sidebarRowSize) var sidebarRowSize

    private var sidebarWidth: CGFloat {
        switch sidebarRowSize {
        case .small: 190
        case .medium: 210
        case .large: 230
        @unknown default: 210
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

    private var sidebarItemFontSize: CGFloat {
        switch sidebarRowSize {
        case .small: 13
        case .medium: 15
        case .large: 16
        @unknown default: 15
        }
    }

    var body: some View {
        // ponytail: plain HStack instead of NavigationSplitView — the sidebar
        // is fixed-width and non-collapsible, so the split view only added
        // an undeletable Liquid Glass divider pill.
        // ponytail: no navigationTitle — like Pelmet, the titlebar shows
        // only traffic lights instead of a long pane name over the sidebar.
        HStack(spacing: 0) {
            sidebar
                .frame(width: sidebarWidth)
            detailView
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                // ponytail: no Divider — like Pelmet, sidebar stays light and
                // the content sits on a darker shade instead of a line.
                .background(.black.opacity(0.2))
        }
    }

    @ViewBuilder
    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 2) {
            ForEach(mainIdentifiers, id: \.self) { identifier in
                SettingsSidebarItem(
                    identifier: identifier,
                    icon: icon(for: identifier),
                    isSelected: navigationState.settingsNavigationIdentifier == identifier,
                    fontSize: sidebarItemFontSize,
                    rowHeight: sidebarItemHeight + 4
                ) {
                    navigationState.settingsNavigationIdentifier = identifier
                }
            }
            Divider()
                .padding(.horizontal, 10)
                .padding(.vertical, 4)
            ForEach(secondaryIdentifiers, id: \.self) { identifier in
                SettingsSidebarItem(
                    identifier: identifier,
                    icon: icon(for: identifier),
                    isSelected: navigationState.settingsNavigationIdentifier == identifier,
                    fontSize: sidebarItemFontSize,
                    rowHeight: sidebarItemHeight + 4
                ) {
                    navigationState.settingsNavigationIdentifier = identifier
                }
            }
        }
        .padding(.horizontal, 8)
        .padding(.top, 12)
        .frame(maxHeight: .infinity, alignment: .top)
    }

    /// Primary items above the divider, mirroring Pelmet's General/Behavior/Menu Bar/Displays group.
    private var mainIdentifiers: [SettingsNavigationIdentifier] {
        SettingsNavigationIdentifier.allCases.filter { $0 != .about }
    }

    /// Secondary items below the divider, mirroring Pelmet's Thanks/About group.
    private var secondaryIdentifiers: [SettingsNavigationIdentifier] {
        [.about]
    }

    @ViewBuilder
    private var detailView: some View {
        switch navigationState.settingsNavigationIdentifier {
        case .general:
            GeneralSettingsPane()
        case .menuBarLayout:
            MenuBarLayoutSettingsPane()
        case .menuBarAppearance:
            MenuBarAppearanceSettingsPane()
        case .hotkeys:
            HotkeysSettingsPane()
        case .advanced:
            AdvancedSettingsPane()
        case .about:
            AboutSettingsPane()
        }
    }

    private func icon(for identifier: SettingsNavigationIdentifier) -> IconResource {
        switch identifier {
        case .general: .systemSymbol("gearshape")
        case .menuBarLayout: .systemSymbol("rectangle.topthird.inset.filled")
        case .menuBarAppearance: .systemSymbol("swatchpalette")
        case .hotkeys: .systemSymbol("keyboard")
        case .advanced: .systemSymbol("gearshape.2")
        case .about: .assetCatalog(.iceCubeStroke)
        }
    }
}

/// A Pelmet-style sidebar row: gray icon + white text by default,
/// translucent blue pill + blue icon/text when selected.
private struct SettingsSidebarItem: View {
    let identifier: SettingsNavigationIdentifier
    let icon: IconResource
    let isSelected: Bool
    let fontSize: CGFloat
    let rowHeight: CGFloat
    let action: () -> Void

    @State private var isHovering = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                icon.view
                    .frame(width: 18, height: 18)
                    .foregroundStyle(isSelected ? .blue : .secondary)
                Text(identifier.localized)
                    .font(.system(size: fontSize, weight: isSelected ? .semibold : .regular))
                    .foregroundStyle(isSelected ? .blue : .primary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .frame(height: rowHeight)
            .background {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(
                        isSelected
                            ? .blue.opacity(0.16)
                            : (isHovering ? .primary.opacity(0.06) : .clear)
                    )
            }
        }
        .buttonStyle(.plain)
        .onHover { isHovering = $0 }
    }
}
