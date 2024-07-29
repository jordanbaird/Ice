//
//  AdvancedSettingsPane.swift
//  Ice
//

import CompactSlider
import SwiftUI

struct AdvancedSettingsPane: View {
    @EnvironmentObject var appState: AppState

    private var menuBarManager: MenuBarManager {
        appState.menuBarManager
    }

    private var manager: AdvancedSettingsManager {
        appState.settingsManager.advancedSettingsManager
    }

    private var showOnHoverDelay: LocalizedStringKey {
        let formatted = manager.showOnHoverDelay.formatted()
        return if manager.showOnHoverDelay == 1 {
            LocalizedStringKey(formatted + " second")
        } else {
            LocalizedStringKey(formatted + " seconds")
        }
    }

    var body: some View {
        Form {
            Section {
                hideApplicationMenus
                showSectionDividers
            }
            Section("Always-Hidden Section") {
                enableAlwaysHiddenSection
                canToggleAlwaysHiddenSection
            }
            Section("Other") {
                showOnHoverDelaySlider
            }
        }
        .formStyle(.grouped)
        .scrollBounceBehavior(.basedOnSize)
    }

    @ViewBuilder
    private var hideApplicationMenus: some View {
        Toggle(isOn: manager.bindings.hideApplicationMenus) {
            Text("Hide application menus when showing menu bar items")
            Text("Make more room in the menu bar by hiding the left application menus if needed")
        }
    }

    @ViewBuilder
    private var showSectionDividers: some View {
        Toggle(isOn: manager.bindings.showSectionDividers) {
            Text("Show section dividers")
            HStack(spacing: 2) {
                Text("Insert divider items")
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
                Text("between sections")
            }
        }
    }

    @ViewBuilder
    private var enableAlwaysHiddenSection: some View {
        Toggle("Enable always-hidden section", isOn: manager.bindings.enableAlwaysHiddenSection)
    }

    @ViewBuilder
    private var canToggleAlwaysHiddenSection: some View {
        if manager.enableAlwaysHiddenSection {
            Toggle(isOn: manager.bindings.canToggleAlwaysHiddenSection) {
                Text("Always-hidden section can be shown")
                if appState.settingsManager.generalSettingsManager.showOnClick {
                    Text("⌥ + click one of Ice's menu bar items, or inside an empty area of the menu bar to show the section")
                } else {
                    Text("⌥ + click one of Ice's menu bar items to show the section")
                }
            }
        }
    }

    @ViewBuilder
    private var showOnHoverDelaySlider: some View {
        LabeledContent {
            CompactSlider(
                value: manager.bindings.showOnHoverDelay,
                in: 0...1,
                step: 0.1,
                handleVisibility: .hovering(width: 1)
            ) {
                Text(showOnHoverDelay)
                    .textSelection(.disabled)
            }
            .compactSliderDisabledHapticFeedback(true)
        } label: {
            Text("Show on hover delay")
                .frame(minHeight: .compactSliderMinHeight)
            Text("The amount of time to wait before showing on hover")
        }
    }
}

#Preview {
    AdvancedSettingsPane()
        .fixedSize()
        .environmentObject(AppState())
}
