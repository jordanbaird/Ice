//
//  MenuBarSettingsPaneAppearanceTab.swift
//  Ice
//

import SwiftUI

struct MenuBarSettingsPaneAppearanceTab: View {
    typealias TintKind = MenuBarManager.TintKind

    @EnvironmentObject var appState: AppState

    var body: some View {
        Form {
            Section {
                tintPicker
            }
            Section {
                shadowToggle
            }
        }
        .formStyle(.grouped)
        .scrollContentBackground(.hidden)
    }

    @ViewBuilder
    private var tintPicker: some View {
        LabeledContent("Menu bar tint") {
            HStack {
                Picker("Menu bar tint", selection: appState.menuBarManager.bindings.tintKind) {
                    Text("None")
                        .tag(TintKind.none)
                    Text("Solid")
                        .tag(TintKind.solid)
                    Text("Gradient")
                        .tag(TintKind.gradient)
                }
                .labelsHidden()

                switch appState.menuBarManager.tintKind {
                case .none:
                    EmptyView()
                case .solid:
                    if appState.menuBarManager.tintColor != nil {
                        Button {
                            appState.menuBarManager.tintColor = nil
                        } label: {
                            Image(systemName: "arrow.counterclockwise")
                        }
                        .help("Reset")
                        .buttonStyle(.plain)
                    }

                    CustomColorPicker(
                        selection: appState.menuBarManager.bindings.tintColor,
                        supportsOpacity: false,
                        mode: .crayon
                    )
                case .gradient:
                    if appState.menuBarManager.tintGradient != .defaultMenuBarTint {
                        Button {
                            appState.menuBarManager.tintGradient = .defaultMenuBarTint
                        } label: {
                            Image(systemName: "arrow.counterclockwise")
                        }
                        .help("Reset")
                        .buttonStyle(.plain)
                    }

                    CustomGradientPicker(
                        gradient: Binding(
                            get: {
                                appState.menuBarManager.tintGradient
                            },
                            set: { gradient in
                                if gradient.stops.isEmpty {
                                    appState.menuBarManager.tintGradient = .defaultMenuBarTint
                                } else {
                                    appState.menuBarManager.tintGradient = gradient
                                }
                            }
                        ),
                        supportsOpacity: false,
                        mode: .crayon
                    )
                    .onChange(of: appState.menuBarManager.tintGradient) { gradient in
                        if gradient.stops.isEmpty {
                            appState.menuBarManager.tintGradient = .defaultMenuBarTint
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
                            appState.menuBarManager.tintGradient = gradient
                        }
                    }
                }
            }
            .frame(height: 24)
        }
    }

    @ViewBuilder
    private var shadowToggle: some View {
        Toggle("Shadow", isOn: appState.menuBarManager.bindings.hasShadow)
    }
}

#Preview {
    let appState = AppState()

    return MenuBarSettingsPaneAppearanceTab()
        .environmentObject(appState)
        .frame(width: 500, height: 300)
}
