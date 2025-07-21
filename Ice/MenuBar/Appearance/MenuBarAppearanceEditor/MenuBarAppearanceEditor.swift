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
    @EnvironmentObject var appearanceManager: MenuBarAppearanceManager

    let location: Location

    private var mainFormPadding: EdgeInsets {
        withMutableCopy(of: EdgeInsets.iceFormDefaultPadding) { insets in
            switch location {
            case .settings: break
            case .panel: insets.top = insets.bottom
            }
        }
    }

    var body: some View {
        bodyContent.safeAreaInset(edge: .bottom, spacing: 0) {
            bottomBar
        }
    }

    @ViewBuilder
    private var bodyContent: some View {
        if appState.menuBarManager.isMenuBarHiddenBySystemUserDefaults {
            cannotEdit
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
        IceForm(padding: mainFormPadding) {
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
        let stack = HStack {
            if
                !appState.menuBarManager.isMenuBarHiddenBySystemUserDefaults,
                appearanceManager.configuration != .defaultConfiguration
            {
                Button("Reset") {
                    appearanceManager.configuration = .defaultConfiguration
                }
            }

            Spacer()

            if case .panel = location {
                DismissWindowButton("Done")
            }
        }
        .controlSize(.large)
        .padding(10)

        if case .panel = location {
            stack.background(.ultraThickMaterial)
        } else {
            stack.background(.bar)
        }
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
        IceLabeledContent("Tint") {
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
                    IceColorPicker(
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
            IceColorPicker(
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
                previewButton
            }
        }
        .frame(height: textFrame.height)
    }

    @ViewBuilder
    private var previewButton: some View {
        switch appearance {
        case .light:
            PreviewButton(configuration: configuration.lightModeConfiguration)
        case .dark:
            PreviewButton(configuration: configuration.darkModeConfiguration)
        }
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
