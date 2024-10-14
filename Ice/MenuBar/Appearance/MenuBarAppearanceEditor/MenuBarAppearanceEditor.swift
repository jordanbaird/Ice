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

    private var mainFormPadding: EdgeInsets {
        switch location {
        case .settings:
            EdgeInsets(top: 20, leading: 20, bottom: 20, trailing: 20)
        case .popover:
            EdgeInsets(top: 0, leading: 20, bottom: 20, trailing: 20)
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            stackHeader
            stackBody
        }
    }

    @ViewBuilder
    private var stackHeader: some View {
        if case .popover(let closePopover) = location {
            ZStack {
                Text("Menu Bar Appearance")
                    .font(.title2)
                    .frame(maxWidth: .infinity, alignment: .center)
                Button("Done", action: closePopover)
                    .controlSize(.large)
                    .frame(maxWidth: .infinity, alignment: .trailing)
            }
            .padding(20)
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
    private var mainForm: some View {
        IceForm(padding: mainFormPadding) {
            IceSection {
                isDynamicToggle
            }
            if appearanceManager.configuration.isDynamic {
                VStack(alignment: .leading) {
                    HStack {
                        Text("Light Appearance")
                            .font(.headline)
                        if case .dark = SystemAppearance.current {
                            PreviewButton(configuration: appearanceManager.configuration.lightModeConfiguration)
                        }
                    }
                    .frame(height: 16)
                    MenuBarPartialAppearanceEditor(configuration: appearanceManager.bindings.configuration.lightModeConfiguration)
                }
                VStack(alignment: .leading) {
                    HStack {
                        Text("Dark Appearance")
                            .font(.headline)
                        if case .light = SystemAppearance.current {
                            PreviewButton(configuration: appearanceManager.configuration.darkModeConfiguration)
                        }
                    }
                    .frame(height: 16)
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
            if
                !appState.menuBarManager.isMenuBarHiddenBySystemUserDefaults,
                appearanceManager.configuration != .defaultConfiguration
            {
                Button("Reset") {
                    appearanceManager.configuration = .defaultConfiguration
                }
                .controlSize(.large)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomLeading)
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

private struct MenuBarPartialAppearanceEditor: View {
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

private struct PreviewButton: View {
    @EnvironmentObject var appearanceManager: MenuBarAppearanceManager

    @State private var frame = CGRect.zero
    @State private var isPressed = false

    let configuration: MenuBarAppearancePartialConfiguration

    var body: some View {
        ZStack {
            DummyButton(isPressed: $isPressed)
                .allowsHitTesting(false)
            Text("Hold to Preview")
                .baselineOffset(1.5)
                .padding(.horizontal, 10)
                .contentShape(Rectangle())
        }
        .fixedSize()
        .simultaneousGesture(
            DragGesture(minimumDistance: 0)
                .onChanged { value in
                    isPressed = frame.contains(value.location)
                }
                .onEnded { _ in
                    isPressed = false
                }
        )
        .onChange(of: isPressed) { _, newValue in
            appearanceManager.previewConfiguration = newValue ? configuration : nil
        }
        .onFrameChange(update: $frame)
    }
}

private struct DummyButton: NSViewRepresentable {
    @Binding var isPressed: Bool

    func makeNSView(context: Context) -> NSButton {
        let button = NSButton()
        button.title = ""
        return button
    }

    func updateNSView(_ nsView: NSButton, context: Context) {
        nsView.isHighlighted = isPressed
    }
}
