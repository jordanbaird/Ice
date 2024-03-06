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

    var body: some View {
        Form {
            Section {
                hideApplicationMenus
                showSectionDividers
            }
        }
        .formStyle(.grouped)
        .scrollContentBackground(.hidden)
        .scrollBounceBehavior(.basedOnSize)
        .frame(maxHeight: .infinity)
    }

    @ViewBuilder
    private var hideApplicationMenus: some View {
        Toggle(isOn: menuBarManager.bindings.hideApplicationMenus) {
            Text("Hide application menus when showing menu bar items")
            Text("Make more room in the menu bar by hiding the left application menus")
        }
    }

    @ViewBuilder
    private var showSectionDividers: some View {
        Toggle(isOn: menuBarManager.bindings.showSectionDividers) {
            Text("Show section dividers")
            HStack(spacing: 2) {
                Text("Divider items")
                if let nsImage = ControlItemImage.builtin(.chevronLarge).nsImage(for: menuBarManager) {
                    HStack(spacing: 0) {
                        Text("(")
                            .font(.body.monospaced().bold())
                        Image(nsImage: nsImage)
                            .padding(.horizontal, -2)
                        Text(")")
                            .font(.body.monospaced().bold())
                    }
                }
                Text("are inserted between adjacent sections")
            }
        }
    }
}
