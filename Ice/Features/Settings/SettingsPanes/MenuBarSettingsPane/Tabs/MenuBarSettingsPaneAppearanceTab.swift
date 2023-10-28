//
//  MenuBarSettingsPaneAppearanceTab.swift
//  Ice
//

import SwiftUI

struct MenuBarSettingsPaneAppearanceTab: View {
    typealias TintKind = MenuBar.TintKind

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
                Picker("Menu bar tint", selection: appState.menuBar.bindings.tintKind) {
                    Text("None")
                        .tag(TintKind.none)
                    Text("Solid")
                        .tag(TintKind.solid)
                    Text("Gradient")
                        .tag(TintKind.gradient)
                }
                .labelsHidden()

                switch appState.menuBar.tintKind {
                case .none:
                    EmptyView()
                case .solid:
                    if appState.menuBar.tintColor != nil {
                        Button {
                            appState.menuBar.tintColor = nil
                        } label: {
                            Image(systemName: "arrow.counterclockwise")
                        }
                        .help("Reset")
                        .buttonStyle(.plain)
                    }

                    CustomColorPicker(
                        selection: appState.menuBar.bindings.tintColor,
                        supportsOpacity: false,
                        mode: .crayon
                    )
                case .gradient:
                    if appState.menuBar.tintGradient != .defaultMenuBarTint {
                        Button {
                            appState.menuBar.tintGradient = .defaultMenuBarTint
                        } label: {
                            Image(systemName: "arrow.counterclockwise")
                        }
                        .help("Reset")
                        .buttonStyle(.plain)
                    }

                    CustomGradientPicker(
                        gradient: Binding(
                            get: {
                                appState.menuBar.tintGradient
                            },
                            set: { gradient in
                                if gradient.stops.isEmpty {
                                    appState.menuBar.tintGradient = .defaultMenuBarTint
                                } else {
                                    appState.menuBar.tintGradient = gradient
                                }
                            }
                        ),
                        supportsOpacity: false,
                        mode: .crayon
                    )
                    .onChange(of: appState.menuBar.tintGradient) { gradient in
                        if gradient.stops.isEmpty {
                            appState.menuBar.tintGradient = .defaultMenuBarTint
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
                            appState.menuBar.tintGradient = gradient
                        }
                    }
                }
            }
            .frame(height: 24)
        }
    }

    @ViewBuilder
    private var shadowToggle: some View {
        Toggle("Shadow", isOn: appState.menuBar.bindings.hasShadow)
    }
}

#Preview {
    let appState = AppState()

    return MenuBarSettingsPaneAppearanceTab()
        .environmentObject(appState)
        .frame(width: 500, height: 300)
}
