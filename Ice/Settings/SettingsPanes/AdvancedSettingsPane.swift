//
//  AdvancedSettingsPane.swift
//  Ice
//

import SwiftUI

struct AdvancedSettingsPane: View {
    @EnvironmentObject var appState: AppState
    @State private var maxSliderLabelWidth: CGFloat = 0

    private var loc: LocalizationManager { appState.localizationManager }

    private var menuBarManager: MenuBarManager {
        appState.menuBarManager
    }

    private var manager: AdvancedSettingsManager {
        appState.settingsManager.advancedSettingsManager
    }

    private func formattedToSeconds(_ interval: TimeInterval) -> String {
        let formatted = interval.formatted()
        return if interval == 1 {
            formatted + " " + loc.localized(.second)
        } else {
            formatted + " " + loc.localized(.seconds)
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
            IceSection(loc.localizedKey(.permissions)) {
                allPermissions
            }
        }
    }

    @ViewBuilder
    private var hideApplicationMenus: some View {
        Toggle(loc.localizedKey(.hideApplicationMenus), isOn: manager.bindings.hideApplicationMenus)
            .annotation(loc.localizedKey(.hideApplicationMenusDetail))
    }

    @ViewBuilder
    private var showSectionDividers: some View {
        Toggle(loc.localizedKey(.showSectionDividers), isOn: manager.bindings.showSectionDividers)
            .annotation {
                HStack(spacing: 2) {
                    Text(loc.localizedKey(.showSectionDividersDetailPrefix))
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
                    Text(loc.localizedKey(.showSectionDividersDetailMiddle))
                }
            }
    }

    @ViewBuilder
    private var enableAlwaysHiddenSection: some View {
        Toggle(loc.localizedKey(.enableAlwaysHiddenSection), isOn: manager.bindings.enableAlwaysHiddenSection)
    }

    @ViewBuilder
    private var canToggleAlwaysHiddenSection: some View {
        if manager.enableAlwaysHiddenSection {
            Toggle(loc.localizedKey(.canToggleAlwaysHiddenSection), isOn: manager.bindings.canToggleAlwaysHiddenSection)
                .annotation {
                    if appState.settingsManager.generalSettingsManager.showOnClick {
                        Text(loc.localizedKey(.toggleAlwaysHiddenSectionDetailWithOption))
                    } else {
                        Text(loc.localizedKey(.toggleAlwaysHiddenSectionDetail))
                    }
                }
        }
    }

    @ViewBuilder
    private var showOnHoverDelaySlider: some View {
        IceLabeledContent {
            IceSlider(
                LocalizedStringKey(formattedToSeconds(manager.showOnHoverDelay)),
                value: manager.bindings.showOnHoverDelay,
                in: 0...1,
                step: 0.1
            )
        } label: {
            Text(loc.localizedKey(.showOnHoverDelay))
                .frame(minHeight: .compactSliderMinHeight)
                .frame(minWidth: maxSliderLabelWidth, alignment: .leading)
                .onFrameChange { frame in
                    maxSliderLabelWidth = max(maxSliderLabelWidth, frame.width)
                }
        }
        .annotation(loc.localizedKey(.showOnHoverDelayDetail))
    }

    @ViewBuilder
    private var tempShowIntervalSlider: some View {
        IceLabeledContent {
            IceSlider(
                LocalizedStringKey(formattedToSeconds(manager.tempShowInterval)),
                value: manager.bindings.tempShowInterval,
                in: 0...30,
                step: 1
            )
        } label: {
            Text(loc.localizedKey(.tempShowInterval))
                .frame(minHeight: .compactSliderMinHeight)
                .frame(minWidth: maxSliderLabelWidth, alignment: .leading)
                .onFrameChange { frame in
                    maxSliderLabelWidth = max(maxSliderLabelWidth, frame.width)
                }
        }
        .annotation(loc.localizedKey(.tempShowIntervalDetail))
    }

    @ViewBuilder
    private var showAllSectionsOnUserDrag: some View {
        Toggle(loc.localizedKey(.showAllSectionsOnUserDrag), isOn: manager.bindings.showAllSectionsOnUserDrag)
    }

    @ViewBuilder
    private var showContextMenuOnRightClick: some View {
        Toggle(loc.localizedKey(.showContextMenuOnRightClick), isOn: manager.bindings.showContextMenuOnRightClick)
    }

    @ViewBuilder
    private var allPermissions: some View {
        ForEach(appState.permissionsManager.allPermissions) { permission in
            IceLabeledContent {
                if permission.hasPermission {
                    Label {
                        Text(loc.localizedKey(.permissionGranted))
                    } icon: {
                        Image(systemName: "checkmark.circle")
                            .foregroundStyle(.green)
                    }
                } else {
                    Button(loc.localizedKey(.grantPermission)) {
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

#Preview {
    AdvancedSettingsPane()
        .fixedSize()
        .environmentObject(AppState())
}
