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
        IceForm {
            IceSection {
                isDynamicToggle
            }
            if appearanceManager.configuration.isDynamic {
                VStack(alignment: .leading) {
                    Text("Light Appearance")
                        .font(.headline)
                    MenuBarPartialAppearanceEditor(configuration: appearanceManager.bindings.configuration.lightModeConfiguration)
                }
                VStack(alignment: .leading) {
                    Text("Dark Appearance")
                        .font(.headline)
                    MenuBarPartialAppearanceEditor(configuration: appearanceManager.bindings.configuration.darkModeConfiguration)
                }
            } else {
                MenuBarPartialAppearanceEditor(configuration: appearanceManager.bindings.configuration.staticConfiguration)
            }
            IceSection("Menu Bar Shape") {
                shapePicker
                isInset
            }
            if case .settings = location {
                IceGroupBox {
                    AnnotationView(
                        alignment: .center,
                        font: .callout.bold()
                    ) {
                        Label {
                            Text("Tip: you can also edit these settings by right-clicking in an empty area of the menu bar")
                        } icon: {
                            Image(systemName: "lightbulb")
                        }
                    }
                }
            }
        }
    }

    @ViewBuilder
    private var isDynamicToggle: some View {
        Toggle("Use dynamic appearance", isOn: appearanceManager.bindings.configuration.isDynamic)
            .annotation("Apply different settings based on the current system appearance")
    }

    @ViewBuilder
    private var cannotEdit: some View {
        Text("Ice cannot edit the appearance of automatically hidden menu bars")
            .font(.title3)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
    }

    @ViewBuilder
    private var shapePicker: some View {
        MenuBarShapePicker()
            .fixedSize(horizontal: false, vertical: true)
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

struct MenuBarPartialAppearanceEditor: View {
    @Binding var configuration: MenuBarAppearancePartialConfiguration

    var body: some View {
        IceSection {
            tintPicker
            shadowToggle
        }
        IceSection {
            borderToggle
            borderColor
            borderWidth
        }
    }

    @ViewBuilder
    private var tintPicker: some View {
        IceLabeledContent("Tint") {
            HStack {
                IcePicker("Tint", selection: $configuration.tintKind) {
                    ForEach(MenuBarTintKind.allCases) { tintKind in
                        Text(tintKind.localized).icePickerID(tintKind)
                    }
                }
                .labelsHidden()

                switch configuration.tintKind {
                case .none:
                    EmptyView()
                case .solid:
                    CustomColorPicker(
                        selection: $configuration.tintColor,
                        supportsOpacity: false,
                        mode: .crayon
                    )
                case .gradient:
                    CustomGradientPicker(
                        gradient: $configuration.tintGradient,
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
        Toggle("Shadow", isOn: $configuration.hasShadow)
    }

    @ViewBuilder
    private var borderToggle: some View {
        Toggle("Border", isOn: $configuration.hasBorder)
    }

    @ViewBuilder
    private var borderColor: some View {
        if configuration.hasBorder {
            IceLabeledContent("Border Color") {
                CustomColorPicker(
                    selection: $configuration.borderColor,
                    supportsOpacity: true,
                    mode: .crayon
                )
            }
        }
    }

    @ViewBuilder
    private var borderWidth: some View {
        if configuration.hasBorder {
            IcePicker(
                "Border Width",
                selection: $configuration.borderWidth
            ) {
                Text("1").icePickerID(1.0)
                Text("2").icePickerID(2.0)
                Text("3").icePickerID(3.0)
            }
        }
    }
}
