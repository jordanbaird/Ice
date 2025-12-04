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
        with(EdgeInsets(all: 20)) { insets in
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
                Text(verbatim: "Menu Bar Appearance".localized(for: appState.settingsManager.generalSettingsManager.language))
                    .font(.title2)
                    .frame(maxWidth: .infinity, alignment: .center)
                Button {
                    closePopover()
                } label: {
                    Text(verbatim: "Done".localized(for: appState.settingsManager.generalSettingsManager.language))
                }
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
            IceSection(header: {
                Text(verbatim: "Menu Bar Shape".localized(for: appState.settingsManager.generalSettingsManager.language))
                    .font(.headline)
            }) {
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
                            Text(verbatim: "Tip: you can also edit these settings by right-clicking in an empty area of the menu bar".localized(for: appState.settingsManager.generalSettingsManager.language))
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
                Button {
                    appearanceManager.configuration = .defaultConfiguration
                } label: {
                    Text(verbatim: "Reset".localized(for: appState.settingsManager.generalSettingsManager.language))
                }
                .controlSize(.large)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomLeading)
            }
        }
    }

    @ViewBuilder
    private var isDynamicToggle: some View {
        Toggle(isOn: appearanceManager.bindings.configuration.isDynamic) {
            Text(verbatim: "Use dynamic appearance".localized(for: appState.settingsManager.generalSettingsManager.language))
        }
        .annotation {
            Text(verbatim: "Apply different settings based on the current system appearance".localized(for: appState.settingsManager.generalSettingsManager.language))
        }
    }

    @ViewBuilder
    private var cannotEdit: some View {
        Text(verbatim: "Ice cannot edit the appearance of automatically hidden menu bars".localized(for: appState.settingsManager.generalSettingsManager.language))
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
            Toggle(isOn: appearanceManager.bindings.configuration.isInset) {
                Text(verbatim: "Use inset shape on screens with notch".localized(for: appState.settingsManager.generalSettingsManager.language))
            }
        }
    }
}

private struct UnlabeledPartialEditor: View {
    @Binding var configuration: MenuBarAppearancePartialConfiguration
    @EnvironmentObject var appState: AppState

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
        IceLabeledContent {
            HStack {
                IcePicker(selection: $configuration.tintKind) {
                    ForEach(MenuBarTintKind.allCases) { tintKind in
                        Text(tintKind.localized).tag(tintKind)
                    }
                } label: {
                    Text(verbatim: "Tint".localized(for: appState.settingsManager.generalSettingsManager.language))
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
        } label: {
            Text(verbatim: "Tint".localized(for: appState.settingsManager.generalSettingsManager.language))
        }
    }

    @ViewBuilder
    private var shadowToggle: some View {
        Toggle(isOn: $configuration.hasShadow) {
            Text(verbatim: "Shadow".localized(for: appState.settingsManager.generalSettingsManager.language))
        }
    }

    @ViewBuilder
    private var borderToggle: some View {
        Toggle(isOn: $configuration.hasBorder) {
            Text(verbatim: "Border".localized(for: appState.settingsManager.generalSettingsManager.language))
        }
    }

    @ViewBuilder
    private var borderColor: some View {
        if configuration.hasBorder {
            IceLabeledContent {
                CustomColorPicker(
                    selection: $configuration.borderColor,
                    supportsOpacity: true,
                    mode: .crayon
                )
            } label: {
                Text(verbatim: "Border Color".localized(for: appState.settingsManager.generalSettingsManager.language))
            }
        }
    }

    @ViewBuilder
    private var borderWidth: some View {
        if configuration.hasBorder {
            IcePicker(
                selection: $configuration.borderWidth
            ) {
                Text("1").tag(1.0)
                Text("2").tag(2.0)
                Text("3").tag(3.0)
            } label: {
                Text(verbatim: "Border Width".localized(for: appState.settingsManager.generalSettingsManager.language))
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
    @EnvironmentObject var appState: AppState


    @State private var frame = CGRect.zero
    @State private var isPressed = false

    let configuration: MenuBarAppearancePartialConfiguration

    var body: some View {
        ZStack {
            DummyButton(isPressed: $isPressed)
                .allowsHitTesting(false)
            Text(verbatim: "Hold to Preview".localized(for: appState.settingsManager.generalSettingsManager.language))
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
