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
                        selection: appState.bindings.menuBar.tintColor,
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
    MenuBarSettingsPaneAppearanceTab()
        .environmentObject(AppState.shared)
        .frame(width: 500, height: 300)
}
