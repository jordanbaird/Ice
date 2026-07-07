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
            IceSection("Screen Shape") {
                ScreenShapePicker()
                    .fixedSize(horizontal: false, vertical: true)
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
    @StateObject private var backgroundProbe = MenuBarBackgroundProbe()

    private static let isBackdropSupported: Bool = {
        if #available(macOS 26.0, *) { true } else { false }
    }()

    var body: some View {
        IceSection {
            appearancePicker
            if configuration.appearanceKind != .none {
                colorPicker
            }
            shadowToggle
        }
        if configuration.appearanceKind == .backdrop {
            backdropWarnings
        }
        IceSection {
            borderToggle
            borderColor
            borderWidth
        }
    }

    @ViewBuilder
    private var appearancePicker: some View {
        IceLabeledContent("Appearance") {
            Menu {
                ForEach(MenuBarAppearanceKind.allCases) { kind in
                    let isUnavailable = kind == .backdrop && !Self.isBackdropSupported
                    Button {
                        guard !isUnavailable else { return }
                        configuration.appearanceKind = kind
                    } label: {
                        if isUnavailable {
                            HStack(spacing: 6) {
                                Text(kind.localized)
                                Text("Requires macOS 26")
                                    .font(.caption2)
                                    .padding(.horizontal, 5)
                                    .padding(.vertical, 1)
                                    .background(.tertiary, in: Capsule())
                            }
                        } else {
                            Text(kind.localized)
                        }
                    }
                    .disabled(isUnavailable)
                }
            } label: {
                Text(configuration.appearanceKind.localized)
            }
            .menuStyle(.borderlessButton)
            .fixedSize()
            .frame(height: 24)
        }
    }

    @ViewBuilder
    private var colorPicker: some View {
        IceLabeledContent("Color") {
            HStack {
                IcePicker("Color", selection: $configuration.tintKind) {
                    Text(MenuBarTintKind.solid.localized).tag(MenuBarTintKind.solid)
                    Text(MenuBarTintKind.gradient.localized).tag(MenuBarTintKind.gradient)
                }
                .labelsHidden()

                let allowsOpacity = configuration.appearanceKind == .backdrop
                switch configuration.tintKind {
                case .none:
                    EmptyView()
                case .solid:
                    CustomColorPicker(
                        selection: $configuration.tintColor,
                        supportsOpacity: allowsOpacity,
                        mode: .crayon
                    )
                case .gradient:
                    CustomGradientPicker(
                        gradient: $configuration.tintGradient,
                        supportsOpacity: allowsOpacity,
                        allowsEmptySelections: false,
                        mode: .crayon
                    )
                }
            }
            .frame(height: 24)
        }
    }

    @ViewBuilder
    private var backdropWarnings: some View {
        let blockers = activeBackdropBlockers
        if !blockers.isEmpty {
            IceGroupBox {
                VStack(alignment: .leading, spacing: 12) {
                    ForEach(blockers) { blocker in
                        backdropWarningRow(blocker)
                    }
                }
            }
        }
    }

    private var activeBackdropBlockers: [BackdropBlocker] {
        var blockers: [BackdropBlocker] = []
        if !Self.isBackdropSupported {
            blockers.append(.requiresMacOS26)
        }
        if backgroundProbe.isOpaqueBackgroundEnabled {
            blockers.append(.opaqueMenuBarBackground)
        }
        if backgroundProbe.isReduceTransparencyEnabled {
            blockers.append(.reduceTransparency)
        }
        return blockers
    }

    @ViewBuilder
    private func backdropWarningRow(_ blocker: BackdropBlocker) -> some View {
        Button {
            if let url = blocker.settingsURL {
                NSWorkspace.shared.open(url)
            }
        } label: {
            HStack(alignment: .top, spacing: 8) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(.orange)
                    .imageScale(.large)
                VStack(alignment: .leading, spacing: 4) {
                    Text(blocker.title)
                        .font(.callout.weight(.semibold))
                    Text(blocker.body)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
                if blocker.settingsURL != nil {
                    Image(systemName: "arrow.up.right.square")
                        .foregroundStyle(.secondary)
                        .imageScale(.medium)
                        .padding(.top, 2)
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(blocker.settingsURL == nil)
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

private enum BackdropBlocker: Hashable, Identifiable {
    case requiresMacOS26
    case opaqueMenuBarBackground
    case reduceTransparency

    var id: Self { self }

    var title: String {
        switch self {
        case .requiresMacOS26:
            "Backdrop requires macOS 26"
        case .opaqueMenuBarBackground:
            "“Show menu bar background” must be off"
        case .reduceTransparency:
            "“Reduce transparency” must be off"
        }
    }

    var body: String {
        switch self {
        case .requiresMacOS26:
            "The backdrop effect relies on the transparent menu bar introduced in macOS 26. Upgrade macOS or pick Tint instead."
        case .opaqueMenuBarBackground:
            "macOS is currently drawing an opaque menu bar background, which will hide the backdrop tint. Open System Settings → Menu Bar and turn off Show menu bar background."
        case .reduceTransparency:
            "Reduce transparency makes the menu bar opaque, which hides the backdrop tint. Open System Settings → Accessibility → Display and turn off Reduce transparency."
        }
    }

    var settingsURL: URL? {
        switch self {
        case .requiresMacOS26:
            nil
        case .opaqueMenuBarBackground:
            URL(string: "x-apple.systempreferences:com.apple.ControlCenter-Settings.extension?MenuBar")
        case .reduceTransparency:
            URL(string: "x-apple.systempreferences:com.apple.Accessibility-Settings.extension?Display")
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
