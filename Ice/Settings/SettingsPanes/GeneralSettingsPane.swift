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

    private var manager: GeneralSettingsManager {
        appState.settingsManager.generalSettingsManager
    }

    private var itemSpacingOffset: LocalizedStringKey {
        if manager.itemSpacingOffset == -16 {
            LocalizedStringKey("none")
        } else if manager.itemSpacingOffset == 0 {
            LocalizedStringKey("default")
        } else if manager.itemSpacingOffset == 16 {
            LocalizedStringKey("max")
        } else {
            LocalizedStringKey(manager.itemSpacingOffset.formatted())
        }
    }

    private var rehideInterval: LocalizedStringKey {
        let formatted = manager.rehideInterval.formatted()
        return if manager.rehideInterval == 1 {
            LocalizedStringKey(formatted + " second")
        } else {
            LocalizedStringKey(formatted + " seconds")
        }
    }

    var body: some View {
        Form {
            Section {
                launchAtLogin
            }
            Section {
                iceIconOptions
            }
            Section {
                iceBarOptions
            }
            Section {
                showOnClick
                showOnHover
                showOnScroll
            }
            Section {
                spacingOptions
            }
            Section {
                autoRehideOptions
            }
        }
        .formStyle(.grouped)
        .scrollContentBackground(.hidden)
        .scrollBounceBehavior(.basedOnSize)
        .frame(maxHeight: .infinity)
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
                Image(nsImage: nsImage)
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
            }
        }
        if manager.showIceIcon {
            LabeledContent {
                Menu {
                    Picker("Ice icon", selection: manager.bindings.iceIcon) {
                        ForEach(ControlItemImageSet.userSelectableIceIcons) { imageSet in
                            label(for: imageSet)
                        }

                        if let lastCustomIceIcon = manager.lastCustomIceIcon {
                            label(for: lastCustomIceIcon)
                        }
                    }
                    .pickerStyle(.inline)
                    .labelsHidden()

                    Button("Choose image…") {
                        isImportingCustomIceIcon = true
                    }
                } label: {
                    label(for: manager.iceIcon)
                }
                .labelStyle(.titleAndIcon)
                .scaledToFit()
                .fixedSize()
            } label: {
                Text("Ice icon")
                Text("Choose a custom icon to show in the menu bar")
            }
            .fileImporter(
                isPresented: $isImportingCustomIceIcon,
                allowedContentTypes: [.image]
            ) { result in
                do {
                    let url = try result.get()
                    if url.startAccessingSecurityScopedResource() {
                        defer {
                            url.stopAccessingSecurityScopedResource()
                        }
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
                    Text("Use template image")
                    Text("Display the icon as a monochrome image matching the system appearance")
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
            Text("Hidden items are shown in a separate bar below the menu bar")
        }
    }

    @ViewBuilder
    private var iceBarLocationPicker: some View {
        Picker(selection: manager.bindings.iceBarLocation) {
            ForEach(IceBarLocation.allCases) { location in
                Text(location.localized).tag(location)
            }
        } label: {
            Text("Location")
            switch manager.iceBarLocation {
            case .default:
                Text("The Ice Bar's location changes based on context")
            case .mousePointer:
                Text("The Ice Bar is centered below the mouse pointer")
            case .iceIcon:
                Text("The Ice Bar is centered below the Ice icon")
            }
        }
    }

    @ViewBuilder
    private var showOnClick: some View {
        Toggle(isOn: manager.bindings.showOnClick) {
            Text("Show on click")
            Text("Click inside an empty area of the menu bar to show hidden items")
        }
    }

    @ViewBuilder
    private var showOnHover: some View {
        Toggle(isOn: manager.bindings.showOnHover) {
            Text("Show on hover")
            Text("Hover over an empty area of the menu bar to show hidden items")
        }
    }

    @ViewBuilder
    private var showOnScroll: some View {
        Toggle(isOn: manager.bindings.showOnScroll) {
            Text("Show on scroll")
            Text("Scroll or swipe in the menu bar to toggle hidden items")
        }
    }

    @ViewBuilder
    private var spacingOptions: some View {
        VStack(alignment: .leading) {
            LabeledContent {
                CompactSlider(
                    value: manager.bindings.itemSpacingOffset,
                    in: -16...16,
                    step: 2,
                    handleVisibility: .hovering(width: 1)
                ) {
                    Text(itemSpacingOffset)
                        .textSelection(.disabled)
                }
                .compactSliderDisabledHapticFeedback(true)
            } label: {
                HStack {
                    Text("Menu bar item spacing")

                    Spacer()

                    Button("Apply") {
                        Task {
                            do {
                                try await appState.spacingManager.applyOffset()
                            } catch {
                                let alert = NSAlert(error: error)
                                alert.runModal()
                            }
                        }
                    }
                    .help("Apply the current spacing")

                    Button("Reset", systemImage: "arrow.counterclockwise.circle.fill") {
                        manager.itemSpacingOffset = 0
                        Task {
                            do {
                                try await appState.spacingManager.applyOffset()
                            } catch {
                                let alert = NSAlert(error: error)
                                alert.runModal()
                            }
                        }
                    }
                    .buttonStyle(.borderless)
                    .labelStyle(.iconOnly)
                    .help("Reset to the default spacing")
                }
            }

            Text("Applying this setting will relaunch all apps with menu bar items. Some apps may need to be manually relaunched.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
    }

    @ViewBuilder
    private var rehideStrategyPicker: some View {
        Picker(selection: manager.bindings.rehideStrategy) {
            ForEach(RehideStrategy.allCases) { strategy in
                Text(strategy.localized).tag(strategy)
            }
        } label: {
            Text("Strategy")
            switch manager.rehideStrategy {
            case .smart:
                Text("Menu bar items are rehidden using a smart algorithm")
            case .timed:
                Text("Menu bar items are rehidden after a fixed amount of time")
            case .focusedApp:
                Text("Menu bar items are rehidden when the focused app changes")
            }
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
}

#Preview {
    GeneralSettingsPane()
        .fixedSize()
        .environmentObject(AppState())
}
