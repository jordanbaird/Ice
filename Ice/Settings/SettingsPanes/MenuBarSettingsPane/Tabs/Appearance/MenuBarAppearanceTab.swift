//
//  MenuBarAppearanceTab.swift
//  Ice
//

import SwiftUI

struct MenuBarAppearanceTab: View {
    @EnvironmentObject var appState: AppState

    private var appearanceManager: MenuBarAppearanceManager {
        appState.menuBarManager.appearanceManager
    }

    var body: some View {
        Form {
            Section {
                tintPicker
                shadowToggle
            }
            Section {
                borderToggle
                borderColor
                borderWidth
            }
            Section("Menu Bar Shape") {
                shapePicker
            }
        }
        .formStyle(.grouped)
        .scrollContentBackground(.hidden)
        .scrollBounceBehavior(.basedOnSize)
    }

    @ViewBuilder
    private var tintPicker: some View {
        LabeledContent("Tint") {
            HStack {
                Picker("Tint", selection: appearanceManager.bindings.tintKind) {
                    ForEach(MenuBarTintKind.allCases) { tintKind in
                        Text(tintKind.localized).tag(tintKind)
                    }
                }
                .labelsHidden()

                switch appearanceManager.tintKind {
                case .none:
                    EmptyView()
                case .solid:
                    CustomColorPicker(
                        selection: appearanceManager.bindings.tintColor,
                        supportsOpacity: false,
                        mode: .crayon
                    )
                case .gradient:
                    CustomGradientPicker(
                        gradient: appearanceManager.bindings.tintGradient,
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
        Toggle("Shadow", isOn: appearanceManager.bindings.hasShadow)
    }

    @ViewBuilder
    private var borderToggle: some View {
        Toggle("Border", isOn: appearanceManager.bindings.hasBorder)
    }

    @ViewBuilder
    private var borderColor: some View {
        if appearanceManager.hasBorder {
            LabeledContent("Border Color") {
                CustomColorPicker(
                    selection: appearanceManager.bindings.borderColor,
                    supportsOpacity: false,
                    mode: .crayon
                )
            }
        }
    }

    @ViewBuilder
    private var borderWidth: some View {
        if appearanceManager.hasBorder {
            Stepper(
                "Border Width",
                value: appearanceManager.bindings.borderWidth,
                in: 1...3,
                step: 1,
                format: .number
            )
        }
    }

    @ViewBuilder
    private var shapePicker: some View {
        MenuBarShapePicker()
    }
}

#Preview {
    MenuBarAppearanceTab()
        .environmentObject(AppState.shared)
        .frame(width: 500, height: 300)
}
