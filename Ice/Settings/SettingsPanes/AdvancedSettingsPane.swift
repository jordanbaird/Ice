//
//  AdvancedSettingsPane.swift
//  Ice
//

import SwiftUI

struct AdvancedSettingsPane: View {
    @EnvironmentObject var appState: AppState

    private var menuBarManager: MenuBarManager {
        appState.menuBarManager
    }

    private var manager: AdvancedSettingsManager {
        appState.settingsManager.advancedSettingsManager
    }

    var body: some View {
        Form {
            Section {
                hideApplicationMenus
            }
            Section {
                showSectionDividers
                showIceIcon
            }
            Section {
                secondaryAction
                secondaryActionModifier
            }
        }
        .formStyle(.grouped)
        .scrollContentBackground(.hidden)
        .scrollBounceBehavior(.basedOnSize)
        .frame(maxHeight: .infinity)
    }

    @ViewBuilder
    private var hideApplicationMenus: some View {
        Toggle(isOn: manager.bindings.hideApplicationMenus) {
            Text("Hide application menus when showing menu bar items")
            Text("Make more room in the menu bar by hiding the left application menus")
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
                Text("between adjacent sections")
            }
        }
    }

    @ViewBuilder
    private var showIceIcon: some View {
        Toggle(isOn: manager.bindings.showIceIcon) {
            Text("Show Ice icon")
            if !manager.showIceIcon {
                Text("You can access \(Constants.appName)'s settings by right-clicking an empty area in the menu bar")
            }
        }
    }

    @ViewBuilder
    private var secondaryAction: some View {
        Picker(selection: manager.bindings.secondaryAction) {
            ForEach(SecondaryAction.allCases, id: \.self) { action in
                Text(action.localized).tag(action)
            }
        } label: {
            Text("Secondary action")
            Text("\(manager.secondaryActionModifier.label) (\(manager.secondaryActionModifier.stringValue)) + click either of \(Constants.appName)'s menu bar items to perform the action")
        }
    }

    @ViewBuilder
    private var secondaryActionModifier: some View {
        Picker("Modifier", selection: manager.bindings.secondaryActionModifier) {
            ForEach(AdvancedSettingsManager.validSecondaryActionModifiers, id: \.self) { modifier in
                Text("\(modifier.stringValue) \(modifier.label)").tag(modifier)
            }
        }
    }
}
