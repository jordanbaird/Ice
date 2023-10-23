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
                    if menuBarManager.tintGradient != .defaultMenuBarTint {
                        Button {
                            menuBarManager.tintGradient = .defaultMenuBarTint
                        } label: {
                            Image(systemName: "arrow.counterclockwise")
                        }
                        .help("Reset")
                        .buttonStyle(.plain)
                    }

                    CustomGradientPicker(
                        gradient: Binding(
                            get: {
                                menuBarManager.tintGradient
                            },
                            set: { gradient in
                                if gradient.stops.isEmpty {
                                    menuBarManager.tintGradient = .defaultMenuBarTint
                                } else {
                                    menuBarManager.tintGradient = gradient
                                }
                            }
                        ),
                        supportsOpacity: false,
                        mode: .crayon
                    )
                    .onChange(of: menuBarManager.tintGradient) { gradient in
                        if gradient.stops.isEmpty {
                            menuBarManager.tintGradient = .defaultMenuBarTint
                        } else if gradient.stops.count == 1 {
                            var gradient = gradient
                            if gradient.stops[0].location >= 0.5 {
                                gradient.stops[0].location = 1
                                let stop = ColorStop(color: .white, location: 0)
                                gradient.stops.append(stop)
                            } else {
                                gradient.stops[0].location = 0
                                let stop = ColorStop(color: .black, location: 1)
                                gradient.stops.append(stop)
                            }
                            menuBarManager.tintGradient = gradient
                        }
                    }
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
