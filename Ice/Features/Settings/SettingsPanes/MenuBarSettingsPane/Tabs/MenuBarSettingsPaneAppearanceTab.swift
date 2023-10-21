//
//  MenuBarSettingsPaneAppearanceTab.swift
//  Ice
//

import SwiftUI

struct MenuBarSettingsPaneAppearanceTab: View {
    typealias TintKind = MenuBarManager.TintKind

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
                Picker("Menu bar tint", selection: menuBarManager.bindings.tintKind) {
                    Text("None")
                        .tag(TintKind.none)
                    Text("Solid")
                        .tag(TintKind.solid)
                    Text("Gradient")
                        .tag(TintKind.gradient)
                }
                .labelsHidden()

                switch menuBarManager.tintKind {
                case .none:
                    EmptyView()
                case .solid:
                    if menuBarManager.tintColor != nil {
                        Button {
                            menuBarManager.tintColor = nil
                        } label: {
                            Image(systemName: "arrow.counterclockwise")
                        }
                        .help("Reset")
                        .buttonStyle(.plain)
                    }
                    CustomColorPicker(
                        selection: menuBarManager.bindings.tintColor,
                        supportsOpacity: false,
                        mode: .crayon
                    )
                case .gradient:
                    if menuBarManager.tintGradient != nil {
                        Button {
                            menuBarManager.tintGradient = nil
                        } label: {
                            Image(systemName: "arrow.counterclockwise")
                        }
                        .help("Reset")
                        .buttonStyle(.plain)
                    }
                    CustomGradientPicker(
                        gradient: Binding(
                            get: {
                                menuBarManager.tintGradient ?? CustomGradient()
                            },
                            set: { gradient in
                                if gradient.stops.isEmpty {
                                    menuBarManager.tintGradient = nil
                                } else {
                                    menuBarManager.tintGradient = gradient
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
