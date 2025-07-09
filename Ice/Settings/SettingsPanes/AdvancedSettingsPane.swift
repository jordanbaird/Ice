//
//  AdvancedSettingsPane.swift
//  Ice
//

import SwiftUI

struct AdvancedSettingsPane: View {
    @EnvironmentObject var appState: AppState
    @ObservedObject var settings: AdvancedSettings
    @State private var maxSliderLabelWidth: CGFloat = 0

    private var menuBarManager: MenuBarManager {
        appState.menuBarManager
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
                enableSecondaryContextMenu
                showOnHoverDelay
                tempShowInterval
            }
            IceSection("Permissions") {
                allPermissions
            }
        }
    }

    @ViewBuilder
    private var enableAlwaysHiddenSection: some View {
        Toggle(
            "Enable the always-hidden section",
            isOn: $settings.enableAlwaysHiddenSection
        )
    }

    @ViewBuilder
    private var showAllSectionsOnUserDrag: some View {
        Toggle(
            "Show all sections when ⌘ Command + dragging menu bar items",
            isOn: $settings.showAllSectionsOnUserDrag
        )
    }

    @ViewBuilder
    private var sectionDividerStyle: some View {
        IcePicker("Section divider style", selection: $settings.sectionDividerStyle) {
            ForEach(SectionDividerStyle.allCases) { style in
                Text(style.localized).tag(style)
            }
        }
    }

    @ViewBuilder
    private var hideApplicationMenus: some View {
        Toggle(
            "Hide app menus when showing menu bar items",
            isOn: $settings.hideApplicationMenus
        )
        .annotation {
            Text(
                """
                Make more room in the menu bar by hiding the current app menus if \
                needed. macOS requires Ice to be visible in the Dock while this setting \
                is in effect.
                """
            )
            .padding(.trailing, 75)
        }
    }

    @ViewBuilder
    private var enableSecondaryContextMenu: some View {
        Toggle(
            "Enable secondary context menu",
            isOn: $settings.enableSecondaryContextMenu
        )
        .annotation {
            Text(
                """
                Right-click in an empty area of the menu bar to display a minimal \
                version of Ice's menu. Disable this if you encounter conflicts with \
                other apps.
                """
            )
            .padding(.trailing, 75)
        }
    }

    @ViewBuilder
    private var showOnHoverDelay: some View {
        IceLabeledContent {
            IceSlider(
                formattedToSeconds(settings.showOnHoverDelay),
                value: $settings.showOnHoverDelay,
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
    private var tempShowInterval: some View {
        IceLabeledContent {
            IceSlider(
                formattedToSeconds(settings.tempShowInterval),
                value: $settings.tempShowInterval,
                in: 0...60,
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
        ForEach(appState.permissions.allPermissions) { permission in
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
