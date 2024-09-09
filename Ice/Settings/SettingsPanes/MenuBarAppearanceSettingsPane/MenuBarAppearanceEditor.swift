//
//  MenuBarAppearanceEditor.swift
//  Ice
//

import SwiftUI

struct MenuBarAppearanceEditor: View {
    enum Location {
        case settings
        case popover(closePopover: () -> Void)
    }

    @EnvironmentObject var appState: AppState
    @EnvironmentObject var appearanceManager: MenuBarAppearanceManager

    let location: Location

    private var footerPadding: CGFloat? {
        if !appState.menuBarManager.isMenuBarHiddenBySystemUserDefaults {
            return nil
        }
        if case .popover = location {
            return nil
        }
        return 0
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            stackHeader
            stackBody
            stackFooter
        }
    }

    @ViewBuilder
    private var stackHeader: some View {
        if case .popover = location {
            Text("Menu Bar Appearance")
                .font(.title2)
                .padding(.top)
                .frame(maxWidth: .infinity, alignment: .center)
        }
    }

    @ViewBuilder
    private var stackBody: some View {
        if appState.menuBarManager.isMenuBarHiddenBySystemUserDefaults {
            cannotEdit
        } else {
            mainForm
        }
    }

    @ViewBuilder
    private var stackFooter: some View {
        HStack {
            if
                !appState.menuBarManager.isMenuBarHiddenBySystemUserDefaults,
                appearanceManager.configuration != .defaultConfiguration
            {
                Button("Reset") {
                    appearanceManager.configuration = .defaultConfiguration
                }
            }
            if case .popover(let closePopover) = location {
                Spacer()
                Button("Done", action: closePopover)
            }
        }
        .padding(.all, footerPadding)
        .controlSize(.large)
    }

    @ViewBuilder
    private var mainForm: some View {
        GroupedForm {
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
                isInset
            }
            if case .settings = location {
                Section {
                    Text("Tip: you can also edit these settings by right-clicking in an empty area of the menu bar")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .center)
                }
            }
        }
    }

    @ViewBuilder
    private var cannotEdit: some View {
        Text("Ice cannot edit the appearance of automatically hidden menu bars")
            .font(.title3)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
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
                    supportsOpacity: true,
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

    @ViewBuilder
    private var isInset: some View {
        if appearanceManager.configuration.shapeKind != .none {
            Toggle(
                "Use inset shape on screens with notch",
                isOn: appearanceManager.bindings.configuration.isInset
            )
        }
    }
}
