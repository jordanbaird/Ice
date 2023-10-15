//
//  MenuBarSettingsPaneAppearanceTab.swift
//  Ice
//

import SwiftUI

struct MenuBarSettingsPaneAppearanceTab: View {
    typealias TintKind = MenuBarAppearanceManager.TintKind

    @EnvironmentObject var menuBar: MenuBar

    var body: some View {
        Form {
            Section {
                tintPicker
            }
        }
        .formStyle(.grouped)
        .scrollContentBackground(.hidden)
    }

    @ViewBuilder
    private var tintPicker: some View {
        LabeledContent("Menu Bar Tint") {
            HStack {
                Picker("Menu Bar Tint", selection: menuBar.appearanceManager.bindings.tintKind) {
                    Text("None")
                        .tag(TintKind.none)
                    Text("Solid")
                        .tag(TintKind.solid)
                    Text("Gradient")
                        .tag(TintKind.gradient)
                }
                .labelsHidden()

                switch menuBar.appearanceManager.tintKind {
                case .none:
                    EmptyView()
                case .solid:
                    CustomColorPicker(
                        selection: menuBar.appearanceManager.bindings.tintColor,
                        supportsOpacity: false,
                        mode: .crayon
                    )
                case .gradient:
                    GradientPicker(
                        gradient: Binding(
                            get: {
                                menuBar.appearanceManager.tintGradient ?? CustomGradient()
                            },
                            set: { gradient in
                                if gradient.stops.isEmpty {
                                    menuBar.appearanceManager.tintGradient = nil
                                } else {
                                    menuBar.appearanceManager.tintGradient = gradient
                                }
                            }
                        ),
                        supportsOpacity: false,
                        mode: .crayon
                    )
                }
            }
            .frame(height: 24)
        }
    }
}

#Preview {
    let menuBar = MenuBar()

    return MenuBarSettingsPaneAppearanceTab()
        .environmentObject(menuBar)
        .frame(width: 500, height: 300)
}
