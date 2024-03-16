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
                secondaryAction
                performSecondaryActionInEmptySpace
                secondaryActionModifier
            }
            Section {
                hideApplicationMenus
            }
            Section {
                showSectionDividers
            }
        }
        .formStyle(.grouped)
        .scrollContentBackground(.hidden)
        .scrollBounceBehavior(.basedOnSize)
        .frame(maxHeight: .infinity)
    }

    @ViewBuilder
    private var secondaryAction: some View {
        Picker(selection: manager.bindings.secondaryAction) {
            ForEach(SecondaryAction.allCases, id: \.self) { action in
                Text(action.localized).tag(action)
            }
        } label: {
            Text("Secondary action")
            Text("\(manager.secondaryActionModifier.combinedValue) + click one of \(Constants.appName)'s menu bar items to perform the action")
        }
    }

    @ViewBuilder
    private var performSecondaryActionInEmptySpace: some View {
        if manager.secondaryAction != .noAction {
            Toggle(isOn: manager.bindings.performSecondaryActionInEmptySpace) {
                Text("Perform in empty menu bar space")
                Text("\(manager.secondaryActionModifier.combinedValue) + click inside an empty area of the menu bar to perform the action")
            }
        }
    }

    @ViewBuilder
    private var secondaryActionModifier: some View {
        if manager.secondaryAction != .noAction {
            Picker("Modifier", selection: manager.bindings.secondaryActionModifier) {
                ForEach(AdvancedSettingsManager.validSecondaryActionModifiers, id: \.self) { modifier in
                    Text("\(modifier.symbolicValue) \(modifier.labelValue)").tag(modifier)
                }
            }
        }
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
}
