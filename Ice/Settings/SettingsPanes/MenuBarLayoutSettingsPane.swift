//
//  MenuBarLayoutSettingsPane.swift
//  Ice
//

import SwiftUI

struct MenuBarLayoutSettingsPane: View {
    @EnvironmentObject var appState: AppState
    @ObservedObject var itemManager: MenuBarItemManager

    private var hasItems: Bool {
        !itemManager.itemCache.managedItems.isEmpty
    }

    var body: some View {
        if !ScreenCapture.cachedCheckPermissions() {
            missingScreenRecordingPermissions
        } else if appState.menuBarManager.isMenuBarHiddenBySystemUserDefaults {
            cannotArrange
        } else {
            IceForm(spacing: 20) {
                header
                layoutBars
            }
        }
    }

    @ViewBuilder
    private var header: some View {
        IceSection {
            VStack(spacing: 3) {
                Text("Drag to arrange your menu bar items into different sections.")
                    .font(.title3.bold())
                Text("Items can also be arranged by ⌘ Command + dragging them in the menu bar.")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.secondary)
            }
            .padding(15)
        }
    }

    @ViewBuilder
    private var layoutBars: some View {
        VStack(spacing: 20) {
            ForEach(MenuBarSection.Name.allCases, id: \.self) { section in
                layoutBar(for: section)
            }
        }
        .opacity(hasItems ? 1 : 0.75)
        .blur(radius: hasItems ? 0 : 5)
        .allowsHitTesting(hasItems)
        .overlay {
            if !hasItems {
                loadingMenuBarItems
            }
        }
    }

    @ViewBuilder
    private var cannotArrange: some View {
        Text("Trincano cannot arrange menu bar items in automatically hidden menu bars.")
            .font(.title3)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
    }

    @ViewBuilder
    private var missingScreenRecordingPermissions: some View {
        VStack {
            Text("Menu bar layout requires screen recording permissions.")
                .font(.title2)

            Button {
                appState.navigationState.settingsNavigationIdentifier = .advanced
            } label: {
                Text("Go to Advanced Settings")
            }
            .buttonStyle(.link)
        }
    }

    @ViewBuilder
    private var loadingMenuBarItems: some View {
        VStack {
            Text("Loading menu bar items…")
            ProgressView()
        }
        .font(.title)
    }

    @ViewBuilder
    private func layoutBar(for name: MenuBarSection.Name) -> some View {
        if
            let section = appState.menuBarManager.section(withName: name),
            section.isEnabled
        {
            let summary = sectionSummary(for: name)

            VStack(alignment: .leading, spacing: 6) {
                HStack(alignment: .firstTextBaseline) {
                    Text(name.localized)
                        .font(.headline)
                    Spacer(minLength: 8)
                    Text("\(summary.itemCount) items")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
                .padding(.horizontal, 8)
                .accessibilityElement(children: .combine)

                LayoutBar(imageCache: appState.imageCache, section: name, isEmpty: summary.isEmpty)

                if summary.showsNotchNote {
                    notchNote(count: summary.behindNotchCount)
                }
            }
        }
    }

    /// The count and notch state of a section, for the header and the note.
    private func sectionSummary(for name: MenuBarSection.Name) -> SectionCountSummary {
        let itemCount = itemManager.itemCache.managedItems(for: name).count
        guard name == .visible else {
            return SectionCountSummary(itemCount: itemCount)
        }
        // Screens without a notch have nothing behind it: no note.
        let behindNotch = NSScreen.screens
            .first { $0.notchGeometry != nil }
            .map { itemManager.notchObscuredItems(on: $0).count } ?? 0
        return SectionCountSummary(itemCount: itemCount, behindNotchCount: behindNotch)
    }

    @ViewBuilder
    private func notchNote(count: Int) -> some View {
        HStack(spacing: 8) {
            UnevenRoundedRectangle(bottomLeadingRadius: 4, bottomTrailingRadius: 4)
                .frame(width: 18, height: 9)
                .accessibilityHidden(true)
            Text("\(count) items are behind the notch on this screen and appear in the Trincano Bar.")
        }
        .font(.callout)
        .foregroundStyle(.secondary)
        .padding(.horizontal, 8)
        .accessibilityElement(children: .combine)
    }
}
