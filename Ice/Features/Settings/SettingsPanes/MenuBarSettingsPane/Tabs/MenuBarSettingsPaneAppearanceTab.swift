//
//  MenuBarSettingsPaneAppearanceTab.swift
//  Ice
//

import SwiftUI

struct MenuBarSettingsPaneAppearanceTab: View {
    typealias TintKind = MenuBarAppearanceManager.TintKind

    @EnvironmentObject var menuBarManager: MenuBarManager

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
        LabeledContent("Menu bar tint") {
            HStack {
                Picker("Menu bar tint", selection: menuBarManager.appearanceManager.bindings.tintKind) {
                    Text("None")
                        .tag(TintKind.none)
                    Text("Solid")
                        .tag(TintKind.solid)
                    Text("Gradient")
                        .tag(TintKind.gradient)
                }
                .labelsHidden()

                switch menuBarManager.appearanceManager.tintKind {
                case .none:
                    EmptyView()
                case .solid:
                    if menuBarManager.appearanceManager.tintColor != nil {
                        Button {
                            menuBarManager.appearanceManager.tintColor = nil
                        } label: {
                            Image(systemName: "arrow.counterclockwise")
                        }
                        .help("Reset")
                        .buttonStyle(.plain)
                    }
                    CustomColorPicker(
                        selection: menuBarManager.appearanceManager.bindings.tintColor,
                        supportsOpacity: false,
                        mode: .crayon
                    )
                case .gradient:
                    if menuBarManager.appearanceManager.tintGradient != nil {
                        Button {
                            menuBarManager.appearanceManager.tintGradient = nil
                        } label: {
                            Image(systemName: "arrow.counterclockwise")
                        }
                        .help("Reset")
                        .buttonStyle(.plain)
                    }
                    CustomGradientPicker(
                        gradient: Binding(
                            get: {
                                menuBarManager.appearanceManager.tintGradient ?? CustomGradient()
                            },
                            set: { gradient in
                                if gradient.stops.isEmpty {
                                    menuBarManager.appearanceManager.tintGradient = nil
                                } else {
                                    menuBarManager.appearanceManager.tintGradient = gradient
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
    let menuBarManager = MenuBarManager()

    return MenuBarSettingsPaneAppearanceTab()
        .environmentObject(menuBarManager)
        .frame(width: 500, height: 300)
}
