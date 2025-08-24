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
                        menuItem(for: imageSet)
                    }
                    .tag(imageSet)
                }
                if let lastCustomIceIcon = settings.lastCustomIceIcon {
                    Button {
                        settings.iceIcon = lastCustomIceIcon
                    } label: {
                        menuItem(for: lastCustomIceIcon)
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
            menuItem(for: settings.iceIcon)
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

        if case .custom = settings.iceIcon.name {
            Toggle("Custom icon uses system theme", isOn: $settings.customIceIconIsTemplate)
                .annotation {
                    Text(
                        """
                        Display the icon as a monochrome image that dynamically adjusts to match \
                        the menu bar's appearance. This setting removes all color from the icon, \
                        but ensures consistent rendering against both light and dark backgrounds.
                        """
                    )
                    .padding(.trailing, 50)
                }
        }
    }

    @ViewBuilder
    private var iceBarOptions: some View {
        useIceBar
        if settings.useIceBar {
            iceBarLocationPicker
        }
    }

    @ViewBuilder
    private var useIceBar: some View {
        Toggle("Use Ice Bar", isOn: $settings.useIceBar)
            .annotation("Show hidden menu bar items in a separate bar below the menu bar.")
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

    @ViewBuilder
    private var showOnClick: some View {
        Toggle("Show on click", isOn: $settings.showOnClick)
            .annotation("Click inside an empty area of the menu bar to show hidden menu bar items.")
    }

    @ViewBuilder
    private var showOnHover: some View {
        Toggle("Show on hover", isOn: $settings.showOnHover)
            .annotation("Hover over an empty area of the menu bar to show hidden menu bar items.")
    }

    @ViewBuilder
    private var showOnScroll: some View {
        Toggle("Show on scroll", isOn: $settings.showOnScroll)
            .annotation("Scroll or swipe in the menu bar to show hidden menu bar items.")
    }

    @ViewBuilder
    private var rehideStrategyPicker: some View {
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
    }

    @ViewBuilder
    private var autoRehideOptions: some View {
        Toggle("Automatically rehide", isOn: $settings.autoRehide)
        if settings.autoRehide {
            if case .timed = settings.rehideStrategy {
                VStack {
                    rehideStrategyPicker
                    IceSlider(
                        rehideIntervalKey,
                        value: $settings.rehideInterval,
                        in: 0...30,
                        step: 1
                    )
                }
            } else {
                rehideStrategyPicker
            }
        }
    }

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
