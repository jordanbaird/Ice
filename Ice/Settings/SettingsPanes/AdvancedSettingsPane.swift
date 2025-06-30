//
//  AdvancedSettingsPane.swift
//  Ice
//

import SwiftUI

struct AdvancedSettingsPane: View {
    @EnvironmentObject var appState: AppState
    @State private var maxSliderLabelWidth: CGFloat = 0

    private var menuBarManager: MenuBarManager {
        appState.menuBarManager
    }

    private var manager: AdvancedSettingsManager {
        appState.settingsManager.advancedSettingsManager
    }

    private func formattedToSeconds(_ interval: TimeInterval) -> LocalizedStringKey {
        let formatted = interval.formatted()
        return if interval == 1 {
            LocalizedStringKey(formatted + " second")
        } else {
            LocalizedStringKey(formatted + " seconds")
        }
    }

    var body: some View {
        IceForm {
            IceSection("Menu Bar Sections") {
                enableAlwaysHiddenSection
                showAllSectionsOnUserDrag
                sectionDividerStyle
            }
            IceSection("Other") {
                hideApplicationMenus
                showContextMenuOnRightClick
                showOnHoverDelaySlider
                tempShowIntervalSlider
            }
            IceSection("Permissions") {
                allPermissions
            }
        }
    }

    @ViewBuilder
    private var hideApplicationMenus: some View {
        Toggle(
            "Hide application menus when showing menu bar items",
            isOn: manager.bindings.hideApplicationMenus
        )
        .annotation {
            Text(
                """
                Make more room in the menu bar by hiding the current app menus if \
                needed. macOS requires Ice to become visible in the Dock while this \
                setting is in effect.
                """
            )
            .padding(.trailing, 75)
        }
    }

    @ViewBuilder
    private var showContextMenuOnRightClick: some View {
        Toggle(
            "Enable secondary context menu",
            isOn: manager.bindings.showContextMenuOnRightClick
        )
        .annotation {
            Text(
                """
                Right-clicking in an empty area of the menu bar displays a minimal \
                version of Ice's menu. Disable this setting if you're experiencing \
                conflicts with other apps.
                """
            )
            .padding(.trailing, 75)
        }
    }

    @ViewBuilder
    private var enableAlwaysHiddenSection: some View {
        Toggle(
            "Enable always-hidden section",
            isOn: manager.bindings.enableAlwaysHiddenSection
        )
    }

    @ViewBuilder
    private var showAllSectionsOnUserDrag: some View {
        Toggle(
            "Show all sections when Command + dragging menu bar items",
            isOn: manager.bindings.showAllSectionsOnUserDrag
        )
    }

    @ViewBuilder
    private var sectionDividerStyle: some View {
        IcePicker("Section divider style", selection: manager.bindings.sectionDividerStyle) {
            ForEach(SectionDividerStyle.allCases) { style in
                Text(style.localized).tag(style)
            }
        }
    }

    @ViewBuilder
    private var showOnHoverDelaySlider: some View {
        IceLabeledContent {
            IceSlider(
                formattedToSeconds(manager.showOnHoverDelay),
                value: manager.bindings.showOnHoverDelay,
                in: 0...1,
                step: 0.1
            )
        } label: {
            Text("Show on hover delay")
                .frame(minWidth: maxSliderLabelWidth, alignment: .leading)
                .onFrameChange { frame in
                    maxSliderLabelWidth = max(maxSliderLabelWidth, frame.width)
                }
        }
        .annotation("The amount of time to wait before showing on hover.")
    }

    @ViewBuilder
    private var tempShowIntervalSlider: some View {
        IceLabeledContent {
            IceSlider(
                formattedToSeconds(manager.tempShowInterval),
                value: manager.bindings.tempShowInterval,
                in: 0...30,
                step: 1
            )
        } label: {
            Text("Temporarily shown item delay")
                .frame(minWidth: maxSliderLabelWidth, alignment: .leading)
                .onFrameChange { frame in
                    maxSliderLabelWidth = max(maxSliderLabelWidth, frame.width)
                }
        }
        .annotation("The amount of time to wait before hiding temporarily shown menu bar items.")
    }

    @ViewBuilder
    private var allPermissions: some View {
        ForEach(appState.permissionsManager.allPermissions) { permission in
            IceLabeledContent {
                if permission.hasPermission {
                    Label {
                        Text("Permission Granted")
                    } icon: {
                        Image(systemName: "checkmark.circle")
                            .foregroundStyle(.green)
                    }
                } else {
                    Button("Grant Permission") {
                        permission.performRequest()
                    }
                }
            } label: {
                Text(permission.title)
            }
            .frame(height: 22)
        }
    }
}
