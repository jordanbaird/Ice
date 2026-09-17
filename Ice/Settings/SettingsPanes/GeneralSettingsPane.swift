//
//  GeneralSettingsPane.swift
//  Ice
//

import LaunchAtLogin
import SwiftUI

struct GeneralSettingsPane: View {
    @EnvironmentObject var appState: AppState
    @ObservedObject var settings: GeneralSettings
    @State private var isImportingCustomIceIcon = false
    @State private var isPresentingError = false
    @State private var presentedError: LocalizedErrorWrapper?
    @State private var isApplyingItemSpacingOffset = false
    @State private var tempItemSpacingOffset: CGFloat = 0

    private var itemSpacingOffsetKey: LocalizedStringKey {
        switch tempItemSpacingOffset {
        case -16: "none"
        case 0: "default"
        case 16: "max"
        default: LocalizedStringKey(tempItemSpacingOffset.formatted())
        }
    }

    private var rehideIntervalKey: LocalizedStringKey {
        let formatted = settings.rehideInterval.formatted()
        if settings.rehideInterval == 1 {
            return LocalizedStringKey(formatted + " second")
        } else {
            return LocalizedStringKey(formatted + " seconds")
        }
    }

    var body: some View {
        IceForm {
            IceSection {
                appOptions
            }
            IceSection {
                iceIconOptions
            }
            IceSection {
                iceBarOptions
            }
            if #unavailable(macOS 27.0) {
                IceSection {
                    showOptions
                }
                IceSection {
                    rehideOptions
                }
                IceSection {
                    spacingOptions
                }
            }
        }
    }

    // MARK: App Options

    @ViewBuilder
    private var appOptions: some View {
        LaunchAtLogin.Toggle()
    }

    // MARK: Ice Icon Options

    @ViewBuilder
    private var iceIconOptions: some View {
        showIceIcon
        if settings.showIceIcon {
            iceIconPicker
        }
    }

    @ViewBuilder
    private var showIceIcon: some View {
        Toggle("Show Ice icon", isOn: $settings.showIceIcon)
            .annotation("Click to show hidden menu bar items. Right-click to access Ice's settings.")
    }

    @ViewBuilder
    private var iceIconPicker: some View {
        let labelKey = LocalizedStringKey("Ice icon")

        IceMenu(labelKey) {
            Picker(labelKey, selection: $settings.iceIcon) {
                ForEach(ControlItemImageSet.userSelectableIceIcons) { imageSet in
                    Button {
                        settings.iceIcon = imageSet
                    } label: {
                        iceIconMenuItem(for: imageSet)
                    }
                    .tag(imageSet)
                }
                if let lastCustomIceIcon = settings.lastCustomIceIcon {
                    Button {
                        settings.iceIcon = lastCustomIceIcon
                    } label: {
                        iceIconMenuItem(for: lastCustomIceIcon)
                    }
                    .tag(lastCustomIceIcon)
                }
            }
            .pickerStyle(.inline)
            .labelsHidden()

            Divider()

            Button("Choose image…") {
                isImportingCustomIceIcon = true
            }
        } title: {
            iceIconMenuItem(for: settings.iceIcon)
        }
        .annotation("Choose a custom icon to show in the menu bar.")
        .fileImporter(
            isPresented: $isImportingCustomIceIcon,
            allowedContentTypes: [.image]
        ) { result in
            do {
                let url = try result.get()
                if url.startAccessingSecurityScopedResource() {
                    defer { url.stopAccessingSecurityScopedResource() }
                    let data = try Data(contentsOf: url)
                    settings.iceIcon = ControlItemImageSet(name: .custom, image: .data(data))
                }
            } catch {
                presentedError = LocalizedErrorWrapper(error)
                isPresentingError = true
            }
        }
        .alert(isPresented: $isPresentingError, error: presentedError) {
            Button("OK") {
                presentedError = nil
                isPresentingError = false
            }
        }

        if case .custom = settings.iceIcon.name {
            Toggle("Custom icon uses dynamic appearance", isOn: $settings.customIceIconIsTemplate)
                .annotation {
                    Text(
                        """
                        Display the icon as a monochrome image that dynamically adjusts to match \
                        the menu bar's appearance. This setting removes all color from the icon, \
                        but ensures consistent rendering with both light and dark backgrounds.
                        """
                    )
                    .padding(.trailing, 50)
                }
        }
    }

    @ViewBuilder
    private func iceIconMenuItem(for imageSet: ControlItemImageSet) -> some View {
        Label {
            Text(imageSet.name.rawValue)
        } icon: {
            if let nsImage = imageSet.hidden.nsImage(for: appState) {
                switch imageSet.name {
                case .custom:
                    Image(size: CGSize(width: 18, height: 18)) { context in
                        context.draw(Image(nsImage: nsImage), in: context.clipBoundingRect)
                    }
                default:
                    Image(nsImage: nsImage)
                }
            }
        }
    }

    // MARK: Ice Bar Options

    @ViewBuilder
    private var iceBarOptions: some View {
        useIceBar
        if settings.useIceBar {
            iceBarLocationPicker
            iceBarItemSpacingSlider
            if #available(macOS 26.0, *) {
                iceBarGlassDarknessSlider
                iceBarBackgroundTransparencySlider
            } else {
                iceBarBackgroundOpacitySlider
            }
        }
    }

    @ViewBuilder
    private var useIceBar: some View {
        Toggle("Use Ice Bar", isOn: $settings.useIceBar)
            .annotation("Show hidden menu bar items in a separate bar below the menu bar.")
    }

    @ViewBuilder
    private var iceBarBackgroundOpacitySlider: some View {
        LabeledContent {
            IceSlider(
                LocalizedStringKey("\(Int((settings.iceBarBackgroundOpacity * 100).rounded()))%"),
                value: $settings.iceBarBackgroundOpacity,
                in: 0...1,
                step: 0.05
            )
        } label: {
            Text("Background opacity")
        }
        .annotation("How opaque the Ice Bar's background is. Items stay fully visible.")
    }

    @ViewBuilder
    private var iceBarItemSpacingSlider: some View {
        LabeledContent {
            endLabeledSlider(
                value: $settings.iceBarItemSpacing,
                in: 0...24,
                minimumSymbol: "arrow.right.and.line.vertical.and.arrow.left",
                maximumSymbol: "arrow.left.and.line.vertical.and.arrow.right"
            )
        } label: {
            Text("Icon spacing")
        }
        .annotation("How much space sits between the icons in the Ice Bar.")
    }

    @ViewBuilder
    private var iceBarGlassDarknessSlider: some View {
        LabeledContent {
            endLabeledSlider(
                value: $settings.iceBarGlassDarkness,
                minimumSymbol: "circle",
                maximumSymbol: "circle.fill"
            )
        } label: {
            Text("Darkness")
        }
        .annotation("The shade over the Ice Bar's glass, from white to black.")
    }

    /// A slider in the style of System Settings: no value shown, and a symbol
    /// at each end for what the ends mean.
    @ViewBuilder
    private func endLabeledSlider(
        value: Binding<Double>,
        in bounds: ClosedRange<Double> = 0...1,
        minimumSymbol: String,
        maximumSymbol: String
    ) -> some View {
        EndLabeledSlider(
            value: value,
            bounds: bounds,
            minimumSymbol: minimumSymbol,
            maximumSymbol: maximumSymbol
        )
    }

    @ViewBuilder
    private var iceBarBackgroundTransparencySlider: some View {
        LabeledContent {
            endLabeledSlider(
                value: $settings.iceBarBackgroundTransparency,
                minimumSymbol: "square.fill",
                maximumSymbol: "square.dashed"
            )
        } label: {
            Text("Transparency")
        }
        .annotation("How much of the glass the shade covers. 100% is bare Liquid Glass; 0% is solid.")
    }

    @ViewBuilder
    private var iceBarLocationPicker: some View {
        IcePicker("Location", selection: $settings.iceBarLocation) {
            ForEach(IceBarLocation.allCases) { location in
                Text(location.localized).tag(location)
            }
        }
        .annotation {
            switch settings.iceBarLocation {
            case .dynamic:
                Text("The Ice Bar's location changes based on context.")
            case .mousePointer:
                Text("The Ice Bar is centered below the mouse pointer.")
            case .iceIcon:
                Text("The Ice Bar is centered below the Ice icon.")
            }
        }
    }

    // MARK: Show Options

    @ViewBuilder
    private var showOptions: some View {
        if #unavailable(macOS 27.0) {
            Toggle("Show on click", isOn: $settings.showOnClick)
                .annotation("Click inside an empty area of the menu bar to show hidden menu bar items.")
        }
        Toggle("Show on hover", isOn: $settings.showOnHover)
            .annotation("Hover over an empty area of the menu bar to show hidden menu bar items.")
        Toggle("Show on scroll", isOn: $settings.showOnScroll)
            .annotation("Scroll or swipe in the menu bar to show hidden menu bar items.")
    }

    // MARK: Rehide Options

    @ViewBuilder
    private var rehideOptions: some View {
        autoRehide
        if settings.autoRehide {
            rehideStrategyPicker
        }
    }

    @ViewBuilder
    private var autoRehide: some View {
        Toggle("Automatically rehide", isOn: $settings.autoRehide)
    }

    @ViewBuilder
    private var rehideStrategyPicker: some View {
        VStack {
            IcePicker("Strategy", selection: $settings.rehideStrategy) {
                ForEach(RehideStrategy.allCases) { strategy in
                    Text(strategy.localized).tag(strategy)
                }
            }
            .annotation {
                switch settings.rehideStrategy {
                case .smart:
                    Text("Menu bar items are rehidden using a smart algorithm.")
                case .timed:
                    Text("Menu bar items are rehidden after a fixed amount of time.")
                case .focusedApp:
                    Text("Menu bar items are rehidden when the focused app changes.")
                }
            }

            if case .timed = settings.rehideStrategy {
                IceSlider(
                    rehideIntervalKey,
                    value: $settings.rehideInterval,
                    in: 0...30,
                    step: 1
                )
            }
        }
    }

    // MARK: Spacing Options

    @ViewBuilder
    private var spacingOptions: some View {
        LabeledContent {
            IceSlider(
                itemSpacingOffsetKey,
                value: $tempItemSpacingOffset,
                in: -16...16,
                step: 2
            )
            .disabled(isApplyingItemSpacingOffset)
        } label: {
            LabeledContent {
                Button("Apply") {
                    applyTempItemSpacingOffset()
                }
                .help("Apply the current spacing")
                .disabled(isApplyingItemSpacingOffset || tempItemSpacingOffset == settings.itemSpacingOffset)

                if isApplyingItemSpacingOffset {
                    ProgressView()
                        .progressViewStyle(.circular)
                        .scaleEffect(0.5)
                        .frame(width: 15, height: 15)
                } else {
                    Button {
                        tempItemSpacingOffset = 0
                        applyTempItemSpacingOffset()
                    } label: {
                        Image(systemName: "arrow.counterclockwise.circle.fill")
                    }
                    .buttonStyle(.borderless)
                    .help("Reset to the default spacing")
                    .disabled(isApplyingItemSpacingOffset || settings.itemSpacingOffset == 0)
                }
            } label: {
                HStack {
                    Text("Menu bar item spacing")
                    BetaBadge()
                }
            }
        }
        .annotation(
            "Applying this setting will relaunch all apps with menu bar items. Some apps may need to be manually relaunched.",
            spacing: 2
        )
        .annotation(spacing: 10) {
            CalloutBox(
                "Note: You may need to log out and back in for this setting to apply properly.",
                systemImage: "exclamationmark.circle"
            )
        }
        .onAppear {
            tempItemSpacingOffset = settings.itemSpacingOffset
        }
    }

    private func applyTempItemSpacingOffset() {
        isApplyingItemSpacingOffset = true
        settings.itemSpacingOffset = tempItemSpacingOffset
        Task {
            do {
                try await appState.spacingManager.applyOffset()
            } catch {
                let alert = NSAlert(error: error)
                alert.runModal()
            }
            isApplyingItemSpacingOffset = false
        }
    }
}

// MARK: - EndLabeledSlider

/// A slider that tracks the pointer in local state and passes the value on at
/// a steady rate.
///
/// Writing every intermediate value straight to the settings republishes the
/// whole pane and saves a default on each one, which makes the knob catch.
private struct EndLabeledSlider: View {
    @Binding var value: Double

    let bounds: ClosedRange<Double>
    let minimumSymbol: String
    let maximumSymbol: String

    @State private var draft: Double?

    private var sliderValue: Binding<Double> {
        Binding {
            draft ?? value
        } set: { newValue in
            // Only the knob moves during a drag. Writing the setting here
            // republishes every row of the settings pane, and rebuilding the
            // icon menus and the launch-at-login toggle is what makes the
            // knob catch. The value is committed when the drag ends.
            draft = newValue
        }
    }

    var body: some View {
        Slider(
            value: sliderValue,
            in: bounds,
            onEditingChanged: { isEditing in
                guard !isEditing else {
                    return
                }
                if let draft {
                    value = draft
                }
                draft = nil
            },
            minimumValueLabel: Image(systemName: minimumSymbol).foregroundStyle(.secondary),
            maximumValueLabel: Image(systemName: maximumSymbol).foregroundStyle(.secondary),
            label: { EmptyView() }
        )
        .controlSize(.small)
    }
}
