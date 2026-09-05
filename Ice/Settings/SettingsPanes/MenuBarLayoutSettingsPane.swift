//
//  MenuBarLayoutSettingsPane.swift
//  Ice
//

import SwiftUI

struct MenuBarLayoutSettingsPane: View {
    private enum LoadState {
        case loading, finished, timedOut
    }

    @EnvironmentObject var appState: AppState
    @ObservedObject var itemManager: MenuBarItemManager
    @State private var loadState = LoadState.loading
    @State private var refreshID = 0

    private var hasItems: Bool {
        !itemManager.itemCache.managedItems.isEmpty
    }

    var body: some View {
        if appState.menuBarManager.isMenuBarHiddenBySystemUserDefaults {
            cannotArrange
        } else if !ScreenCapture.cachedCheckPermissions() {
            missingScreenRecordingPermissions
        } else {
            layoutContent
        }
    }

    private var layoutContent: some View {
        IceForm(alignment: .leading, spacing: 24) {
            header
            layoutBars
            if #available(macOS 27.0, *) {
                Label("Hold ⌘ and drag in the menu bar. Items to the left of Ice are hidden.", systemImage: "command")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, 4)
            }
        }
        .task(id: refreshID) {
            loadState = .loading
            if #available(macOS 27.0, *) {
                appState.menuBarManager.macOS27Controller.beginLayoutEditing()
                do { try await Task.sleep(for: .milliseconds(200)) } catch { return }
            }
            await itemManager.cacheItemsRegardless(
                ignoringRecentMovement: true,
                refreshingAllOwners: true
            )
            guard !Task.isCancelled else { return }
            loadState = .finished
            await appState.imageCache.updateCacheWithoutChecks(
                sections: MenuBarSection.Name.allCases
            )
        }
        .task(id: refreshID) {
            do { try await Task.sleep(for: .seconds(8)) } catch { return }
            // A nonresponsive AX owner must not leave an endless spinner.
            if loadState == .loading { loadState = .timedOut }
        }
        .onDisappear {
            if #available(macOS 27.0, *) {
                appState.menuBarManager.macOS27Controller.endLayoutEditing()
            }
        }
    }

    @ViewBuilder
    private var header: some View {
        if #available(macOS 27.0, *) {
            VStack(alignment: .leading, spacing: 6) {
                Text("Arrange your menu bar")
                    .font(.system(size: 20, weight: .semibold))
                Text("Drag items between sections, or change their order. Changes appear in your menu bar.")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.top, 14)
            .padding(.horizontal, 4)
        } else {
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
    }

    @ViewBuilder
    private var layoutBars: some View {
        if hasItems {
            VStack(spacing: 22) {
                ForEach(MenuBarSection.Name.allCases, id: \.self) { section in
                    layoutBar(for: section)
                }
            }
        } else {
            loadingMenuBarItems
                .frame(maxWidth: .infinity, minHeight: 240)
        }
    }

    @ViewBuilder
    private var cannotArrange: some View {
        Text("Ice cannot arrange menu bar items in automatically hidden menu bars.")
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
        VStack(spacing: 12) {
            switch loadState {
            case .loading:
                Text("Loading menu bar items…")
                ProgressView()
            case .finished, .timedOut:
                Image(systemName: "menubar.rectangle")
                    .font(.system(size: 24))
                    .foregroundStyle(.secondary)
                Text(loadState == .timedOut ? "Menu bar items are taking longer than expected." : "No movable menu bar items found.")
                    .font(.headline)
                Text("Try again once your menu bar apps are ready. You can check permissions in Advanced Settings.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 360)
                Button("Try Again") {
                    loadState = .loading
                    refreshID += 1
                }
                .buttonStyle(.bordered)
            }
        }
        .padding(24)
    }

    @ViewBuilder
    private func layoutBar(for name: MenuBarSection.Name) -> some View {
        if
            let section = appState.menuBarManager.section(withName: name),
            section.isEnabled
        {
            VStack(alignment: .leading, spacing: 10) {
                if #available(macOS 27.0, *) {
                    HStack(alignment: .top, spacing: 10) {
                        Image(systemName: name == .visible ? "eye" : "eye.slash")
                            .font(.system(size: 14, weight: .medium))
                            .foregroundStyle(.secondary)
                            .frame(width: 20, height: 20)
                        VStack(alignment: .leading, spacing: 3) {
                            Text(name.localized).font(.system(size: 13, weight: .semibold))
                            Text(sectionDescription(name))
                                .font(.system(size: 11))
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        Text(itemManager.itemCache[name].count.formatted())
                            .font(.system(size: 11, weight: .medium).monospacedDigit())
                            .foregroundStyle(.secondary)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 3)
                            .background(.primary.opacity(0.045), in: Capsule())
                    }
                    .padding(.horizontal, 4)
                } else {
                    Text(name.localized).font(.headline).padding(.leading, 8)
                }

                LayoutBar(
                    imageCache: appState.imageCache,
                    section: name,
                    isEmpty: itemManager.itemCache[name].isEmpty
                )
            }
        }
    }

    private func sectionDescription(_ section: MenuBarSection.Name) -> LocalizedStringKey {
        switch section {
        case .visible: "Always within reach, to the right of Ice."
        case .hidden: "Click Ice to show or hide these items."
        case .alwaysHidden: "Kept out of the way until you choose to reveal them."
        }
    }
}
