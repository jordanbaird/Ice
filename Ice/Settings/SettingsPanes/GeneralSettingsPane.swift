//
//  GeneralSettingsPane.swift
//  Ice
//

import CompactSlider
import LaunchAtLogin
import SwiftUI

struct GeneralSettingsPane: View {
    @EnvironmentObject var appState: AppState
    @State private var isImportingCustomIceIcon = false
    @State private var isPresentingError = false
    @State private var presentedError: AnyLocalizedError?
    @State private var isApplyingOffset = false
    @State private var tempItemSpacingOffset: CGFloat = 0 // Temporary state for the slider

    private var manager: GeneralSettingsManager {
        appState.settingsManager.generalSettingsManager
    }

    private var itemSpacingOffset: LocalizedStringKey {
        localizedOffsetString(for: manager.itemSpacingOffset)
    }

    private func localizedOffsetString(for offset: CGFloat) -> LocalizedStringKey {
        switch offset {
        case -16:
            return LocalizedStringKey("none")
        case 0:
            return LocalizedStringKey("default")
        case 16:
            return LocalizedStringKey("max")
        default:
            return LocalizedStringKey(offset.formatted())
        }
    }

    private var rehideInterval: LocalizedStringKey {
        let formatted = manager.rehideInterval.formatted()
        if manager.rehideInterval == 1 {
            return LocalizedStringKey(formatted + " second")
        } else {
            return LocalizedStringKey(formatted + " seconds")
        }
    }

    private var hasSliderValueChanged: Bool {
        tempItemSpacingOffset != manager.itemSpacingOffset
    }

    private var isActualValueDifferentFromDefault: Bool {
        manager.itemSpacingOffset != 0
    }

    var body: some View {
        ScrollView {
            Group {
                IceSection {
                    launchAtLogin
                }
                IceSection {
                    iceIconOptions
                }
                IceSection {
                    iceBarOptions
                }
                IceSection {
                    showOnClick
                    showOnHover
                    showOnScroll
                }
                IceSection {
                    autoRehideOptions
                }
                IceSection {
                    spacingOptions
                }
            }
            .padding()
        }
        .scrollContentBackground(.hidden)
        .scrollBounceBehavior(.basedOnSize)
        .alert(isPresented: $isPresentingError, error: presentedError) {
            Button("OK") {
                presentedError = nil
                isPresentingError = false
            }
        }
    }

    @ViewBuilder
    private var launchAtLogin: some View {
        LaunchAtLogin.Toggle()
    }

    @ViewBuilder
    private func label(for imageSet: ControlItemImageSet) -> some View {
        Label {
            Text(imageSet.name.rawValue)
        } icon: {
            if let nsImage = imageSet.hidden.nsImage(for: appState) {
                switch imageSet.name {
                case .custom:
                    Image(size: CGSize(width: 18, height: 18)) { context in
                        context.draw(
                            Image(nsImage: nsImage),
                            in: context.clipBoundingRect
                        )
                    }
                default:
                    Image(nsImage: nsImage)
                }
            }
        }
        .tag(imageSet)
    }

    @ViewBuilder
    private var iceIconOptions: some View {
        Toggle(isOn: manager.bindings.showIceIcon) {
            Text("Show Ice icon")
            if !manager.showIceIcon {
                Text("You can still access Ice's settings by right-clicking an empty area in the menu bar")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
        if manager.showIceIcon {
            IcePicker(selection: manager.bindings.iceIcon) {
                ForEach(ControlItemImageSet.userSelectableIceIcons) { imageSet in
                    label(for: imageSet)
                }
                if let lastCustomIceIcon = manager.lastCustomIceIcon {
                    label(for: lastCustomIceIcon)
                }
                Divider()
                Button("Choose image…") {
                    isImportingCustomIceIcon = true
                }
            } label: {
                Text("Ice icon")
                Text("Choose a custom icon to show in the menu bar")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            .fileImporter(
                isPresented: $isImportingCustomIceIcon,
                allowedContentTypes: [.image]
            ) { result in
                do {
                    let url = try result.get()
                    if url.startAccessingSecurityScopedResource() {
                        defer { url.stopAccessingSecurityScopedResource() }
                        let data = try Data(contentsOf: url)
                        manager.iceIcon = ControlItemImageSet(name: .custom, image: .data(data))
                    }
                } catch {
                    presentedError = AnyLocalizedError(error: error)
                    isPresentingError = true
                }
            }

            if case .custom = manager.iceIcon.name {
                Toggle(isOn: manager.bindings.customIceIconIsTemplate) {
                    Text("Apply system theme to icon")
                    Text("Display the icon as a monochrome image matching the system appearance")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    @ViewBuilder
    private var iceBarOptions: some View {
        useIceBar
        if manager.useIceBar {
            iceBarLocationPicker
        }
    }

    @ViewBuilder
    private var useIceBar: some View {
        Toggle(isOn: manager.bindings.useIceBar) {
            Text("Use Ice Bar")
            Text("Show hidden menu bar items in a separate bar below the menu bar")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
    }

    @ViewBuilder
    private var iceBarLocationPicker: some View {
        IcePicker(selection: manager.bindings.iceBarLocation) {
            ForEach(IceBarLocation.allCases) { location in
                Text(location.localized).tag(location)
            }
        } label: {
            Text("Location")
            let annotation = switch manager.iceBarLocation {
            case .default:
                Text("The Ice Bar's location changes based on context")
            case .mousePointer:
                Text("The Ice Bar is centered below the mouse pointer")
            case .iceIcon:
                Text("The Ice Bar is centered below the Ice icon")
            }
            annotation
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
    }

    @ViewBuilder
    private var showOnClick: some View {
        Toggle(isOn: manager.bindings.showOnClick) {
            Text("Show on click")
            Text("Click inside an empty area of the menu bar to show hidden menu bar items")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
    }

    @ViewBuilder
    private var showOnHover: some View {
        Toggle(isOn: manager.bindings.showOnHover) {
            Text("Show on hover")
            Text("Hover over an empty area of the menu bar to show hidden menu bar items")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
    }

    @ViewBuilder
    private var showOnScroll: some View {
        Toggle(isOn: manager.bindings.showOnScroll) {
            Text("Show on scroll")
            Text("Scroll or swipe in the menu bar to toggle hidden menu bar items")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
    }

    @ViewBuilder
    private var spacingOptions: some View {
        VStack(alignment: .leading) {
            IceLabeledContent {
                CompactSlider(
                    value: $tempItemSpacingOffset,
                    in: -16...16,
                    step: 2,
                    handleVisibility: .hovering(width: 1)
                ) {
                    Text(localizedOffsetString(for: tempItemSpacingOffset))
                        .textSelection(.disabled)
                }
                .compactSliderDisabledHapticFeedback(true)
                .disabled(isApplyingOffset)
            } label: {
                HStack {
                    Text("Menu bar item spacing")

                    Spacer()

                    Button("Apply") {
                        applyOffset()
                    }
                    .help("Apply the current spacing")
                    .disabled(isApplyingOffset || !hasSliderValueChanged)

                    if isApplyingOffset {
                        ProgressView()
                            .progressViewStyle(CircularProgressViewStyle())
                            .scaleEffect(0.5)
                            .frame(width: 15, height: 15)
                    } else {
                        Button {
                            resetOffsetToDefault()
                        } label: {
                            Image(systemName: "arrow.counterclockwise.circle.fill")
                        }
                        .buttonStyle(.borderless)
                        .help("Reset to the default spacing")
                        .disabled(isApplyingOffset || !isActualValueDifferentFromDefault)
                    }
                }
            }

            Text("Applying this setting will relaunch all apps with menu bar items. Some apps may need to be manually relaunched.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .onAppear {
            tempItemSpacingOffset = manager.itemSpacingOffset
        }
    }

    @ViewBuilder
    private var rehideStrategyPicker: some View {
        IcePicker(selection: manager.bindings.rehideStrategy) {
            ForEach(RehideStrategy.allCases) { strategy in
                Text(strategy.localized).tag(strategy)
            }
        } label: {
            Text("Strategy")
            let annotation = switch manager.rehideStrategy {
            case .smart:
                Text("Menu bar items are rehidden using a smart algorithm")
            case .timed:
                Text("Menu bar items are rehidden after a fixed amount of time")
            case .focusedApp:
                Text("Menu bar items are rehidden when the focused app changes")
            }
            annotation
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
    }

    @ViewBuilder
    private var autoRehideOptions: some View {
        Toggle(isOn: manager.bindings.autoRehide) {
            Text("Automatically rehide")
        }
        if manager.autoRehide {
            if case .timed = manager.rehideStrategy {
                VStack(alignment: .trailing) {
                    rehideStrategyPicker
                    CompactSlider(
                        value: manager.bindings.rehideInterval,
                        in: 0...30,
                        step: 1,
                        handleVisibility: .hovering(width: 1)
                    ) {
                        Text(rehideInterval)
                    }
                    .compactSliderDisabledHapticFeedback(true)
                }
            } else {
                rehideStrategyPicker
            }
        }
    }

    /// Apply menu bar spacing offset.
    private func applyOffset() {
        isApplyingOffset = true
        manager.itemSpacingOffset = tempItemSpacingOffset
        Task {
            do {
                try await appState.spacingManager.applyOffset()
            } catch {
                let alert = NSAlert(error: error)
                alert.runModal()
            }
            isApplyingOffset = false
        }
    }

    /// Reset menu bar spacing offset to default.
    private func resetOffsetToDefault() {
        tempItemSpacingOffset = 0
        manager.itemSpacingOffset = tempItemSpacingOffset
        applyOffset()
    }
}

#Preview {
    GeneralSettingsPane()
        .fixedSize()
        .environmentObject(AppState())
}
