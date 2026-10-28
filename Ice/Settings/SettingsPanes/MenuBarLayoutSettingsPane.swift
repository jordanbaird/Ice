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
                if #available(macOS 27.0, *) {
                    StuckOverflowWarning(concealer: appState.concealer27)
                }
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
                Group {
                    if #available(macOS 27.0, *) {
                        Text("macOS orders the items within each section.")
                    } else {
                        Text("Items can also be arranged by ⌘ Command + dragging them in the menu bar.")
                    }
                }
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
            VStack(alignment: .leading) {
                Text(name.localized)
                    .font(.headline)
                    .padding(.leading, 8)

                LayoutBar(imageCache: appState.imageCache, section: name)
            }
        }
    }
}

/// Tells the user when macOS has left items folded away beside the notch, and offers the one
/// thing that brings them back.
///
/// macOS 27 folds the items that do not fit on a built-in display's bar, which is what plugging
/// a second display in sets off. Concealing the hidden applications frees the room again, but the
/// fold is not reconsidered: the "«" that reaches the folded items goes away with the items still
/// behind it. Only the application that owns an item can lay it out afresh, by being relaunched —
/// measured, an item created by anything else is laid out alone and leaves the folded ones where
/// they are. Which application is missing cannot be read off the bar, so they are all offered and
/// the user picks the one they can see is gone.
@available(macOS 27.0, *)
private struct StuckOverflowWarning: View {
    @ObservedObject var concealer: Concealer27

    var body: some View {
        if concealer.isOverflowStuck {
            IceSection {
                VStack(alignment: .leading, spacing: 10) {
                    VStack(alignment: .leading, spacing: 3) {
                        Text("Some items are folded away on the built-in display.")
                            .font(.headline)
                        Text("macOS stopped laying them out when Ice freed the space beside the notch, and left no control to reach them. Relaunching the application whose item is missing brings it back.")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    if !concealer.visibleApplications.isEmpty {
                        FlowRow {
                            ForEach(concealer.visibleApplications, id: \.bundleID) { application in
                                Button {
                                    concealer.relaunch(bundleID: application.bundleID)
                                } label: {
                                    Text("Relaunch \(application.name)")
                                }
                            }
                        }
                    }
                }
                .padding(15)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }
}

/// Lays its content out in a row that wraps, so a long list of applications stays readable.
private struct FlowRow<Content: View>: View {
    @ViewBuilder var content: Content

    var body: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 8) { content }
            VStack(alignment: .leading, spacing: 8) { content }
        }
    }
}
