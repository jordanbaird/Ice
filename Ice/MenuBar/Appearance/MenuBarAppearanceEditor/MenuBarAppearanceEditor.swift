//
//  MenuBarAppearanceEditor.swift
//  Ice
//

import SwiftUI

struct MenuBarAppearanceEditor: View {
    enum Location {
        case settings
        case panel
    }

    @EnvironmentObject var appState: AppState
    @ObservedObject var appearanceManager: MenuBarAppearanceManager
    @Environment(\.dismissWindow) private var dismissWindow
    @State private var isResetPromptPresented = false

    let location: Location

    var body: some View {
        if #available(macOS 26.0, *) {
            bodyContent
                .safeAreaBar(edge: .bottom, spacing: 0) {
                    bottomBar
                }
        } else {
            VStack(spacing: 0) {
                bodyContent
                bottomBar
            }
        }
    }

    @ViewBuilder
    private var bodyContent: some View {
        if appState.menuBarManager.isMenuBarHiddenBySystemUserDefaults {
            cannotEdit
        } else if #available(macOS 26.0, *) {
            mainForm
                .scrollEdgeEffectStyle(.hard, for: .vertical)
        } else {
            mainForm
        }
    }

    @ViewBuilder
    private var cannotEdit: some View {
        Text("Ice cannot edit the appearance of automatically hidden menu bars.")
            .font(.title3)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
    }

    @ViewBuilder
    private var mainForm: some View {
        IceForm {
            if
                case .settings = location,
                appState.settings.advanced.enableSecondaryContextMenu
            {
                CalloutBox(
                    "Tip: You can also edit these settings by right-clicking in an empty area of the menu bar.",
                    systemImage: "lightbulb"
                )
            }
            IceSection {
                isDynamicToggle
            }
            if appearanceManager.configuration.isDynamic {
                LabeledPartialEditor(configuration: $appearanceManager.configuration, appearance: .light)
                LabeledPartialEditor(configuration: $appearanceManager.configuration, appearance: .dark)
            } else {
                StaticPartialEditor(configuration: $appearanceManager.configuration)
            }
            IceSection("Menu Bar Shape") {
                shapePicker
                isInset
            }
        }
    }

    @ViewBuilder
    private var bottomBar: some View {
        HStack {
            if case .panel = location {
                Button("Done") {
                    dismissWindow()
                }
            }

            Spacer()

            if
                !appState.menuBarManager.isMenuBarHiddenBySystemUserDefaults,
                appearanceManager.configuration != .defaultConfiguration
            {
                Button("Reset") {
                    isResetPromptPresented = true
                }
                .alert("Reset Menu Bar Appearance", isPresented: $isResetPromptPresented) {
                    Button("Cancel", role: .cancel) {
                        isResetPromptPresented = false
                    }
                    Button("Reset", role: .destructive) {
                        appearanceManager.configuration = .defaultConfiguration
                        isResetPromptPresented = false
                    }
                } message: {
                    Text("This action cannot be undone.")
                }
            }
        }
        .buttonBorderShape(.capsule)
        .padding(10)
    }

    @ViewBuilder
    private var isDynamicToggle: some View {
        Toggle("Use dynamic appearance", isOn: $appearanceManager.configuration.isDynamic)
            .annotation("Apply different settings based on the current system appearance.")
    }

    @ViewBuilder
    private var shapePicker: some View {
        MenuBarShapePicker(configuration: $appearanceManager.configuration)
            .fixedSize(horizontal: false, vertical: true)
    }

    @ViewBuilder
    private var isInset: some View {
        if appearanceManager.configuration.shapeKind != .noShape {
            Toggle(
                "Use inset shape on screens with notch",
                isOn: $appearanceManager.configuration.isInset
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
        LabeledContent("Tint") {
            HStack {
                IcePicker("Tint", selection: $configuration.tintKind) {
                    ForEach(MenuBarTintKind.allCases) { tintKind in
                        Text(tintKind.localized).tag(tintKind)
                    }
                }
                .labelsHidden()

                switch configuration.tintKind {
                case .noTint:
                    EmptyView()
                case .solid:
                    ColorPicker(
                        configuration.tintKind.localized,
                        selection: $configuration.tintColor,
                        supportsOpacity: false
                    )
                    .labelsHidden()
                case .gradient:
                    IceGradientPicker(
                        configuration.tintKind.localized,
                        gradient: $configuration.tintGradient,
                        supportsOpacity: false
                    )
                    .labelsHidden()
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
            ColorPicker(
                "Border Color",
                selection: $configuration.borderColor,
                supportsOpacity: true
            )
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
    @Binding var configuration: MenuBarAppearanceConfigurationV2
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
                PreviewButton(appearance: appearance)
            }
        }
        .frame(height: textFrame.height)
    }

    @ViewBuilder
    private var partialEditor: some View {
        switch appearance {
        case .light:
            UnlabeledPartialEditor(configuration: $configuration.lightModeConfiguration)
        case .dark:
            UnlabeledPartialEditor(configuration: $configuration.darkModeConfiguration)
        }
    }
}

private struct StaticPartialEditor: View {
    @Binding var configuration: MenuBarAppearanceConfigurationV2

    var body: some View {
        UnlabeledPartialEditor(configuration: $configuration.staticConfiguration)
    }
}

private struct PreviewButton: View {
    @EnvironmentObject private var appState: AppState
    @State private var isPressed = false

    let appearance: SystemAppearance

    private var manager: MenuBarAppearanceManager {
        appState.appearanceManager
    }

    private var previewConfiguration: MenuBarAppearancePartialConfiguration {
        switch appearance {
        case .light:
            manager.configuration.lightModeConfiguration
        case .dark:
            manager.configuration.darkModeConfiguration
        }
    }

    var body: some View {
        Button("Hold to Preview") { }
            .buttonStyle(PreviewButtonStyle(isPressed: $isPressed))
            .onChange(of: isPressed) {
                manager.previewConfiguration = isPressed ? previewConfiguration : nil
            }
    }
}

private struct PreviewButtonStyle: ButtonStyle {
    @Binding var isPressed: Bool

    private var borderShape: some InsettableShape {
        if #available(macOS 26.0, *) {
            AnyInsettableShape(Capsule(style: .continuous))
        } else {
            AnyInsettableShape(RoundedRectangle(cornerRadius: 6, style: .circular))
        }
    }

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .padding(.horizontal, 10)
            .padding(.vertical, 3)
            .background {
                borderShape
                    .fill(configuration.isPressed ? .tertiary : .quaternary)
                    .opacity(configuration.isPressed ? 0.5 : 0.75)
            }
            .contentShape([.focusEffect, .interaction], borderShape)
            .onChange(of: configuration.isPressed) { _, newValue in
                isPressed = newValue
            }
    }
}
