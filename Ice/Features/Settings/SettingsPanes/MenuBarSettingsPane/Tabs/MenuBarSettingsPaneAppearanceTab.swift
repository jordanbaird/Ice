//
//  MenuBarSettingsPaneAppearanceTab.swift
//  Ice
//

import SwiftUI

struct MenuBarSettingsPaneAppearanceTab: View {
    @EnvironmentObject var menuBar: MenuBar

    private var tint: Binding<CGColor> {
        Binding(
            get: { menuBar.appearanceManager.tint ?? .black },
            set: { menuBar.appearanceManager.tint = $0 }
        )
    }

    var body: some View {
        Form {
            Section {
                tintColorPicker
            }
        }
        .formStyle(.grouped)
        .scrollContentBackground(.hidden)
        .background(.ultraThinMaterial)
    }

    @ViewBuilder
    private var tintColorPicker: some View {
        LabeledContent("Menu Bar Tint") {
            Color.clear
                .overlay(alignment: .trailing) {
                    if menuBar.appearanceManager.tint != nil {
                        Button {
                            menuBar.appearanceManager.tint = nil
                        } label: {
                            Image(systemName: "arrow.counterclockwise")
                        }
                        .help("Reset")
                        .buttonStyle(.borderless)
                    }
                }

            ColorPicker(
                "Menu Bar Tint",
                selection: tint,
                supportsOpacity: false
            )
            .labelsHidden()
        }
    }
}

#Preview {
    let menuBar = MenuBar()

    return MenuBarSettingsPaneAppearanceTab()
        .environmentObject(menuBar)
        .frame(width: 500, height: 300)
}
