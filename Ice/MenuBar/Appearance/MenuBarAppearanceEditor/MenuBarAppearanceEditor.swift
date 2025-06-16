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
        with(EdgeInsets.iceFormDefaultPadding) { insets in
            switch location {
            case .settings: break
            case .popover: insets.top = 0
            }
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
                LabeledPartialEditor(appearance: .light)
                LabeledPartialEditor(appearance: .dark)
            } else {
                StaticPartialEditor()
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

private struct UnlabeledPartialEditor: View {
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
                        Text(tintKind.localized).tag(tintKind)
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
                Text("1").tag(1.0)
                Text("2").tag(2.0)
                Text("3").tag(3.0)
            }
        }
    }
}

private struct LabeledPartialEditor: View {
    @EnvironmentObject var appearanceManager: MenuBarAppearanceManager
    @State private var currentAppearance = SystemAppearance.current
    @State private var textFrame = CGRect.zero

    let appearance: SystemAppearance

    var body: some View {
        IceSection(options: .plain) {
            labelStack
        } content: {
            partialEditor
        }
        .onReceive(NSApp.publisher(for: \.effectiveAppearance)) { _ in
            currentAppearance = .current
        }
    }

    @ViewBuilder
    private var labelStack: some View {
        HStack {
            Text(appearance.titleKey)
                .font(.headline)
                .onFrameChange(update: $textFrame)

            if currentAppearance != appearance {
                previewButton
            }
        }
        .frame(height: textFrame.height)
    }

    @ViewBuilder
    private var previewButton: some View {
        switch appearance {
        case .light:
            PreviewButton(configuration: appearanceManager.configuration.lightModeConfiguration)
        case .dark:
            PreviewButton(configuration: appearanceManager.configuration.darkModeConfiguration)
        }
    }

    @ViewBuilder
    private var partialEditor: some View {
        switch appearance {
        case .light:
            UnlabeledPartialEditor(configuration: appearanceManager.bindings.configuration.lightModeConfiguration)
        case .dark:
            UnlabeledPartialEditor(configuration: appearanceManager.bindings.configuration.darkModeConfiguration)
        }
    }
}

private struct StaticPartialEditor: View {
    @EnvironmentObject var appearanceManager: MenuBarAppearanceManager

    var body: some View {
        UnlabeledPartialEditor(configuration: appearanceManager.bindings.configuration.staticConfiguration)
    }
}

private struct PreviewButton: View {
    private struct DummyButton: NSViewRepresentable {
        @Binding var isPressed: Bool

        func makeNSView(context: Context) -> NSButton {
            let button = NSButton()
            button.title = ""
            button.bezelStyle = .accessoryBarAction
            return button
        }

        func updateNSView(_ nsView: NSButton, context: Context) {
            nsView.isHighlighted = isPressed
        }
    }

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
