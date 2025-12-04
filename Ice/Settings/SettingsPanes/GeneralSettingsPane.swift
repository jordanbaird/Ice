//
//  GeneralSettingsPane.swift
//  Ice
//

import LaunchAtLogin
import SwiftUI

struct GeneralSettingsPane: View {
    @EnvironmentObject var appState: AppState
    @State private var isImportingCustomIceIcon = false
    @State private var isPresentingError = false
    @State private var presentedError: LocalizedErrorWrapper?
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
            return LocalizedStringKey("none".localized(for: manager.language))
        case 0:
            return LocalizedStringKey("default".localized(for: manager.language))
        case 16:
            return LocalizedStringKey("max".localized(for: manager.language))
        default:
            return LocalizedStringKey(offset.formatted())
        }
    }

    private var rehideIntervalKey: LocalizedStringKey {
        let formatted = manager.rehideInterval.formatted()
        if manager.rehideInterval == 1 {
            return LocalizedStringKey(formatted + " second".localized(for: manager.language))
        } else {
            return LocalizedStringKey(formatted + " seconds".localized(for: manager.language))
        }
    }

    private var hasSpacingSliderValueChanged: Bool {
        tempItemSpacingOffset != manager.itemSpacingOffset
    }

    private var isActualOffsetDifferentFromDefault: Bool {
        manager.itemSpacingOffset != 0
    }

    var body: some View {
        IceForm {
            IceSection {
                launchAtLogin
                languagePicker
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
        .alert(isPresented: $isPresentingError, error: presentedError) {
            Button {
                presentedError = nil
                isPresentingError = false
            } label: {
                Text(verbatim: "OK".localized(for: manager.language))
            }
        }
    }

    @ViewBuilder
    private var launchAtLogin: some View {
        Toggle(isOn: Binding(
            get: { LaunchAtLogin.isEnabled },
            set: { LaunchAtLogin.isEnabled = $0 }
        )) {
            Text(verbatim: "Launch at login".localized(for: manager.language))
        }
    }

    @ViewBuilder
    private var languagePicker: some View {
        IcePicker(selection: manager.bindings.language) {
            ForEach(Language.allCases) { language in
                Text(language.localized).tag(language)
            }
        } label: {
            Text(verbatim: "Language".localized(for: manager.language))
        }
    }

    @ViewBuilder
    private func menuItem(for imageSet: ControlItemImageSet) -> some View {
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
    }

    @ViewBuilder
    private var iceIconOptions: some View {
        Toggle(isOn: manager.bindings.showIceIcon) {
            Text(verbatim: "Show Ice icon".localized(for: manager.language))
        }
        .annotation {
            if !manager.showIceIcon {
                Text(verbatim: "You can still access Ice's settings by right-clicking an empty area in the menu bar".localized(for: manager.language))
            }
        }
        if manager.showIceIcon {
            IceMenu {
                Picker(selection: manager.bindings.iceIcon) {
                    ForEach(ControlItemImageSet.userSelectableIceIcons) { imageSet in
                        Button {
                            manager.iceIcon = imageSet
                        } label: {
                            menuItem(for: imageSet)
                        }
                        .tag(imageSet)
                    }
                    if let lastCustomIceIcon = manager.lastCustomIceIcon {
                        Button {
                            manager.iceIcon = lastCustomIceIcon
                        } label: {
                            menuItem(for: lastCustomIceIcon)
                        }
                        .tag(lastCustomIceIcon)
                    }
                } label: {
                    Text(verbatim: "Ice icon".localized(for: manager.language))
                }
                .pickerStyle(.inline)
                .labelsHidden()

                Divider()

                Button {
                    isImportingCustomIceIcon = true
                } label: {
                    Text(verbatim: "Choose image…".localized(for: manager.language))
                }
            } title: {
                menuItem(for: manager.iceIcon)
            } label: {
                Text(verbatim: "Ice icon".localized(for: manager.language))
            }
            .annotation {
                Text(verbatim: "Choose a custom icon to show in the menu bar".localized(for: manager.language))
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
                    presentedError = LocalizedErrorWrapper(error)
                    isPresentingError = true
                }
            }

            if case .custom = manager.iceIcon.name {
                Toggle(isOn: manager.bindings.customIceIconIsTemplate) {
                    Text(verbatim: "Apply system theme to icon".localized(for: manager.language))
                }
                .annotation {
                    Text(verbatim: "Display the icon as a monochrome image matching the system appearance".localized(for: manager.language))
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
            Text(verbatim: "Use Ice Bar".localized(for: manager.language))
        }
        .annotation {
            Text(verbatim: "Show hidden menu bar items in a separate bar below the menu bar".localized(for: manager.language))
        }
    }

    @ViewBuilder
    private var iceBarLocationPicker: some View {
        IcePicker(selection: manager.bindings.iceBarLocation) {
            ForEach(IceBarLocation.allCases) { location in
                Text(location.localized).tag(location)
            }
        } label: {
            Text(verbatim: "Location".localized(for: manager.language))
        }
        .annotation {
            switch manager.iceBarLocation {
            case .dynamic:
                Text(verbatim: "The Ice Bar's location changes based on context".localized(for: manager.language))
            case .mousePointer:
                Text(verbatim: "The Ice Bar is centered below the mouse pointer".localized(for: manager.language))
            case .iceIcon:
                Text(verbatim: "The Ice Bar is centered below the Ice icon".localized(for: manager.language))
            }
        }
    }

    @ViewBuilder
    private var showOnClick: some View {
        Toggle(isOn: manager.bindings.showOnClick) {
            Text(verbatim: "Show on click".localized(for: manager.language))
        }
        .annotation {
            Text(verbatim: "Click inside an empty area of the menu bar to show hidden menu bar items".localized(for: manager.language))
        }
    }

    @ViewBuilder
    private var showOnHover: some View {
        Toggle(isOn: manager.bindings.showOnHover) {
            Text(verbatim: "Show on hover".localized(for: manager.language))
        }
        .annotation {
            Text(verbatim: "Hover over an empty area of the menu bar to show hidden menu bar items".localized(for: manager.language))
        }
    }

    @ViewBuilder
    private var showOnScroll: some View {
        Toggle(isOn: manager.bindings.showOnScroll) {
            Text(verbatim: "Show on scroll".localized(for: manager.language))
        }
        .annotation {
            Text(verbatim: "Scroll or swipe in the menu bar to toggle hidden menu bar items".localized(for: manager.language))
        }
    }

    @ViewBuilder
    private var spacingOptions: some View {
        IceLabeledContent {
            IceSlider(
                localizedOffsetString(for: tempItemSpacingOffset),
                value: $tempItemSpacingOffset,
                in: -16...16,
                step: 2
            )
            .disabled(isApplyingOffset)
        } label: {
            IceLabeledContent {
                Button {
                    applyOffset()
                } label: {
                    Text(verbatim: "Apply".localized(for: manager.language))
                }
                .help(LocalizedStringKey("Apply the current spacing".localized(for: manager.language)))
                .disabled(isApplyingOffset || !hasSpacingSliderValueChanged)

                if isApplyingOffset {
                    ProgressView()
                        .progressViewStyle(.circular)
                        .scaleEffect(0.5)
                        .frame(width: 15, height: 15)
                } else {
                    Button {
                        resetOffsetToDefault()
                    } label: {
                        Image(systemName: "arrow.counterclockwise.circle.fill")
                    }
                    .buttonStyle(.borderless)
                    .help(LocalizedStringKey("Reset to the default spacing".localized(for: manager.language)))
                    .disabled(isApplyingOffset || !isActualOffsetDifferentFromDefault)
                }
            } label: {
                HStack {
                    Text(verbatim: "Menu bar item spacing".localized(for: manager.language))
                    BetaBadge()
                }
            }
        }
        .annotation(spacing: 2) {
            Text(verbatim: "Applying this setting will relaunch all apps with menu bar items. Some apps may need to be manually relaunched.".localized(for: manager.language))
        }
        .annotation(spacing: 10, font: .callout.bold()) {
            IceGroupBox {
                Label {
                    Text(verbatim: "Note: You may need to log out and back in for this setting to apply properly.".localized(for: manager.language))
                } icon: {
                    Image(systemName: "exclamationmark.circle")
                }
                .frame(maxWidth: .infinity)
            }
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
            Text(verbatim: "Strategy".localized(for: manager.language))
        }
        .annotation {
            switch manager.rehideStrategy {
            case .smart:
                Text(verbatim: "Menu bar items are rehidden using a smart algorithm".localized(for: manager.language))
            case .timed:
                Text(verbatim: "Menu bar items are rehidden after a fixed amount of time".localized(for: manager.language))
            case .focusedApp:
                Text(verbatim: "Menu bar items are rehidden when the focused app changes".localized(for: manager.language))
            }
        }
    }

    @ViewBuilder
    private var autoRehideOptions: some View {
        Toggle(isOn: manager.bindings.autoRehide) {
            Text(verbatim: "Automatically rehide".localized(for: manager.language))
        }
        if manager.autoRehide {
            if case .timed = manager.rehideStrategy {
                VStack {
                    rehideStrategyPicker
                    IceSlider(
                        rehideIntervalKey,
                        value: manager.bindings.rehideInterval,
                        in: 0...30,
                        step: 1
                    )
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
