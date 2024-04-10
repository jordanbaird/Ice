//
//  MenuBarAppearanceTab.swift
//  Ice
//

import SwiftUI

struct MenuBarAppearanceTab: View {
    enum Location {
        case settings
        case popover(closePopover: () -> Void)
    }

    @EnvironmentObject var appState: AppState

    let location: Location

    private var appearanceManager: MenuBarAppearanceManager {
        appState.menuBarManager.appearanceManager
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            headerText
            mainForm
            HStack {
                Button("Reset") {
                    appearanceManager.configuration = .defaultConfiguration
                }
                if case let .popover(closePopover) = location {
                    Spacer()
                    Button("Done", action: closePopover)
                }
            }
            .padding()
            .controlSize(.large)
        }
    }

    @ViewBuilder
    private var headerText: some View {
        switch location {
        case .settings:
            Text("Menu Bar Appearance")
                .font(.title2)
                .annotation {
                    Text("Tip: you can also edit these settings by right-clicking in an empty area of the menu bar")
                }
                .padding(.top)
                .padding(.horizontal, 20)
        case .popover:
            HStack {
                Spacer()
                Text("Menu Bar Appearance")
                    .font(.title2)
                    .padding(.top)
                    .padding(.horizontal, 20)
                Spacer()
            }
        }
    }

    @ViewBuilder
    private var mainForm: some View {
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
                Picker("Tint", selection: appearanceManager.bindings.configuration.tintKind) {
                    ForEach(MenuBarTintKind.allCases) { tintKind in
                        Text(tintKind.localized).tag(tintKind)
                    }
                }
                .labelsHidden()

                switch appearanceManager.configuration.tintKind {
                case .none:
                    EmptyView()
                case .solid:
                    CustomColorPicker(
                        selection: appearanceManager.bindings.configuration.tintColor,
                        supportsOpacity: false,
                        mode: .crayon
                    )
                case .gradient:
                    CustomGradientPicker(
                        gradient: appearanceManager.bindings.configuration.tintGradient,
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
        Toggle("Shadow", isOn: appearanceManager.bindings.configuration.hasShadow)
    }

    @ViewBuilder
    private var borderToggle: some View {
        Toggle("Border", isOn: appearanceManager.bindings.configuration.hasBorder)
    }

    @ViewBuilder
    private var borderColor: some View {
        if appearanceManager.configuration.hasBorder {
            LabeledContent("Border Color") {
                CustomColorPicker(
                    selection: appearanceManager.bindings.configuration.borderColor,
                    supportsOpacity: false,
                    mode: .crayon
                )
            }
        }
    }

    @ViewBuilder
    private var borderWidth: some View {
        if appearanceManager.configuration.hasBorder {
            Picker(
                "Border Width",
                selection: appearanceManager.bindings.configuration.borderWidth
            ) {
                Text("1").tag(1.0)
                Text("2").tag(2.0)
                Text("3").tag(3.0)
            }
        }
    }

    @ViewBuilder
    private var shapePicker: some View {
        MenuBarShapePicker()
    }
}

#Preview {
    MenuBarAppearanceTab(location: .settings)
        .environmentObject(AppState.shared)
        .buttonStyle(.custom)
        .frame(width: 500, height: 300)
}
