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

    private var generalSettingsManager: GeneralSettingsManager {
        appState.settingsManager.generalSettingsManager
    }

    private func formattedToSeconds(_ interval: TimeInterval) -> LocalizedStringKey {
        let formatted = interval.formatted()
        return if interval == 1 {
            LocalizedStringKey(formatted + " second".localized(for: generalSettingsManager.language))
        } else {
            LocalizedStringKey(formatted + " seconds".localized(for: generalSettingsManager.language))
        }
    }

    var body: some View {
        IceForm {
            IceSection {
                hideApplicationMenus
                showSectionDividers
                showAllSectionsOnUserDrag
                showContextMenuOnRightClick
            }
            IceSection {
                enableAlwaysHiddenSection
                canToggleAlwaysHiddenSection
            }
            IceSection {
                showOnHoverDelaySlider
                tempShowIntervalSlider
            }
            IceSection(header: {
                Text(verbatim: "Permissions".localized(for: generalSettingsManager.language))
                    .font(.headline)
            }) {
                allPermissions
            }
        }
    }

    @ViewBuilder
    private var hideApplicationMenus: some View {
        Toggle(isOn: manager.bindings.hideApplicationMenus) {
            Text(verbatim: "Hide application menus when showing menu bar items".localized(for: generalSettingsManager.language))
        }
        .annotation {
            Text(verbatim: "Make more room in the menu bar by hiding the left application menus if needed".localized(for: generalSettingsManager.language))
        }
    }

    @ViewBuilder
    private var showSectionDividers: some View {
        Toggle(isOn: manager.bindings.showSectionDividers) {
            Text(verbatim: "Show section dividers".localized(for: generalSettingsManager.language))
        }
        .annotation {
            HStack(spacing: 2) {
                Text(verbatim: "Insert divider items".localized(for: generalSettingsManager.language))
                if let nsImage = ControlItemImage.builtin(.chevronLarge).nsImage(for: appState) {
                    HStack(spacing: 0) {
                        Text("(")
                            .font(.body.monospaced().bold())
                        Image(nsImage: nsImage)
                            .padding(.horizontal, -2)
                        Text(")")
                            .font(.body.monospaced().bold())
                    }
                }
                Text(verbatim: "between sections".localized(for: generalSettingsManager.language))
            }
        }
    }

    @ViewBuilder
    private var enableAlwaysHiddenSection: some View {
        Toggle(isOn: manager.bindings.enableAlwaysHiddenSection) {
            Text(verbatim: "Enable always-hidden section".localized(for: generalSettingsManager.language))
        }
    }

    @ViewBuilder
    private var canToggleAlwaysHiddenSection: some View {
        if manager.enableAlwaysHiddenSection {
            Toggle(isOn: manager.bindings.canToggleAlwaysHiddenSection) {
                Text(verbatim: "Always-hidden section can be shown".localized(for: generalSettingsManager.language))
            }
            .annotation {
                if appState.settingsManager.generalSettingsManager.showOnClick {
                    Text(verbatim: "Option + click one of Ice's menu bar items, or inside an empty area of the menu bar to show the section".localized(for: generalSettingsManager.language))
                } else {
                    Text(verbatim: "Option + click one of Ice's menu bar items to show the section".localized(for: generalSettingsManager.language))
                }
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
            Text(verbatim: "Show on hover delay".localized(for: generalSettingsManager.language))
                .frame(minHeight: .compactSliderMinHeight)
                .frame(minWidth: maxSliderLabelWidth, alignment: .leading)
                .onFrameChange { frame in
                    maxSliderLabelWidth = max(maxSliderLabelWidth, frame.width)
                }
        }
        .annotation {
            Text(verbatim: "The amount of time to wait before showing on hover".localized(for: generalSettingsManager.language))
        }
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
            Text(verbatim: "Temporarily shown item delay".localized(for: generalSettingsManager.language))
                .frame(minHeight: .compactSliderMinHeight)
                .frame(minWidth: maxSliderLabelWidth, alignment: .leading)
                .onFrameChange { frame in
                    maxSliderLabelWidth = max(maxSliderLabelWidth, frame.width)
                }
        }
        .annotation {
            Text(verbatim: "The amount of time to wait before hiding temporarily shown menu bar items".localized(for: generalSettingsManager.language))
        }
    }

    @ViewBuilder
    private var showAllSectionsOnUserDrag: some View {
        Toggle(isOn: manager.bindings.showAllSectionsOnUserDrag) {
            Text(verbatim: "Show all sections when Command + dragging menu bar items".localized(for: generalSettingsManager.language))
        }
    }

    @ViewBuilder
    private var showContextMenuOnRightClick: some View {
        Toggle(isOn: manager.bindings.showContextMenuOnRightClick) {
            Text(verbatim: "Show context menu on right click".localized(for: generalSettingsManager.language))
        }
    }

    @ViewBuilder
    private var allPermissions: some View {
        ForEach(appState.permissionsManager.allPermissions) { permission in
            IceLabeledContent {
                if permission.hasPermission {
                    Label {
                        Text(verbatim: "Permission Granted".localized(for: generalSettingsManager.language))
                    } icon: {
                        Image(systemName: "checkmark.circle")
                            .foregroundStyle(.green)
                    }
                } else {
                    Button {
                        permission.performRequest()
                    } label: {
                        Text(verbatim: "Grant Permission".localized(for: generalSettingsManager.language))
                    }
                }
            } label: {
                Text(verbatim: permission.title.localized(for: generalSettingsManager.language))
            }
            .frame(height: 22)
        }
    }
}

#Preview {
    AdvancedSettingsPane()
        .fixedSize()
        .environmentObject(AppState())
}
