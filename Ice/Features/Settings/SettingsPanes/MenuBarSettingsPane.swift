//
//  MenuBarSettingsPane.swift
//  Ice
//

import SwiftUI

struct MenuBarSettingsPane: View {
    @EnvironmentObject var appState: AppState

    var body: some View {
        Form {
            Section {
                tintPicker
            }
            Section {
                shadowToggle
            }
            Section {
                borderToggle
                borderColor
                borderWidth
            }
        }
        .formStyle(.grouped)
        .scrollContentBackground(.hidden)
    }

    @ViewBuilder
    private var tintPicker: some View {
        LabeledContent("Menu Bar Tint") {
            HStack {
                Picker("Menu Bar Tint", selection: appState.bindings.menuBar.tintKind) {
                    Text("None")
                        .tag(MenuBar.TintKind.none)
                    Text("Solid")
                        .tag(MenuBar.TintKind.solid)
                    Text("Gradient")
                        .tag(MenuBar.TintKind.gradient)
                }
                .labelsHidden()

                switch appState.menuBar.tintKind {
                case .none:
                    EmptyView()
                case .solid:
                    CustomColorPicker(
                        selection: appState.bindings.menuBar.tintColor,
                        supportsOpacity: false,
                        mode: .crayon
                    )
                case .gradient:
                    CustomGradientPicker(
                        gradient: appState.bindings.menuBar.tintGradient,
                        supportsOpacity: false,
                        allowsEmptySelections: false,
                        mode: .crayon
                    )
                }
            }
            .frame(height: 24)
        }
    }

    @ViewBuilder
    private var shadowToggle: some View {
        Toggle("Shadow", isOn: appState.bindings.menuBar.hasShadow)
    }

    @ViewBuilder
    private var borderToggle: some View {
        Toggle("Border", isOn: appState.bindings.menuBar.hasBorder)
    }

    @ViewBuilder
    private var borderColor: some View {
        if appState.menuBar.hasBorder {
            LabeledContent("Border Color") {
                CustomColorPicker(
                    selection: appState.bindings.menuBar.borderColor,
                    supportsOpacity: false,
                    mode: .crayon
                )
            }
        }
    }

    @ViewBuilder
    private var borderWidth: some View {
        if appState.menuBar.hasBorder {
            Stepper(
                "Border Width",
                value: appState.bindings.menuBar.borderWidth,
                in: 1...5,
                step: 1,
                format: .number
            )
        }
    }
}

#Preview {
    MenuBarSettingsPane()
        .environmentObject(AppState.shared)
        .frame(width: 500, height: 300)
}
