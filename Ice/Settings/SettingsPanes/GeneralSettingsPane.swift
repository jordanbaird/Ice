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
    @State private var presentedError: LocalizedErrorBox?

    private var menuBarManager: MenuBarManager {
        appState.menuBarManager
    }

    private var rehideInterval: LocalizedStringKey {
        let formatted = menuBarManager.rehideInterval.formatted()
        return if menuBarManager.rehideInterval == 1 {
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
            if menuBarManager.showIceIcon {
                Section {
                    iceIconOptions
                }
            }
            Section {
                showOnClick
                showOnHover
                showOnScroll
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
            if let nsImage = imageSet.hidden.nsImage(for: menuBarManager) {
                Image(nsImage: nsImage)
            }
        }
        .tag(imageSet)
    }

    @ViewBuilder
    private var iceIconOptions: some View {
        LabeledContent {
            Menu {
                Picker("\(Constants.appName) icon", selection: menuBarManager.bindings.iceIcon) {
                    ForEach(ControlItemImageSet.userSelectableImageSets) { imageSet in
                        label(for: imageSet)
                    }

                    if let lastCustomIceIcon = menuBarManager.lastCustomIceIcon {
                        label(for: lastCustomIceIcon)
                    }
                }
                .pickerStyle(.inline)
                .labelsHidden()

                Button("Choose image…") {
                    isImportingCustomIceIcon = true
                }
            } label: {
                label(for: menuBarManager.iceIcon)
            }
            .labelStyle(.titleAndIcon)
            .scaledToFit()
            .fixedSize()
        } label: {
            Text("\(Constants.appName) icon")
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
                    menuBarManager.iceIcon = ControlItemImageSet(
                        name: .custom,
                        hidden: .data(data),
                        visible: .data(data)
                    )
                }
            } catch {
                presentedError = LocalizedErrorBox(error: error)
                isPresentingError = true
            }
        }

        if case .custom = menuBarManager.iceIcon.name {
            Toggle(isOn: menuBarManager.bindings.customIceIconIsTemplate) {
                Text("Use template image")
                Text("Display the icon as a monochrome image matching the system appearance")
            }
        }
    }

    @ViewBuilder
    private var showOnClick: some View {
        Toggle(isOn: menuBarManager.bindings.showOnClick) {
            Text("Show on click")
            Text("Click inside an empty area of the menu bar to show hidden items")
        }
    }

    @ViewBuilder
    private var showOnHover: some View {
        Toggle(isOn: menuBarManager.bindings.showOnHover) {
            Text("Show on hover")
            Text("Hover over an empty area of the menu bar to show hidden items")
        }
    }

    @ViewBuilder
    private var showOnScroll: some View {
        Toggle(isOn: menuBarManager.bindings.showOnScroll) {
            Text("Show on scroll")
            Text("Scroll or swipe in the menu bar to toggle hidden items")
        }
    }

    @ViewBuilder
    private var rehideStrategyPicker: some View {
        Picker(selection: menuBarManager.bindings.rehideStrategy) {
            ForEach(RehideStrategy.allCases) { strategy in
                Text(strategy.localized).tag(strategy)
            }
        } label: {
            Text("Strategy")
            switch menuBarManager.rehideStrategy {
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
        Toggle(isOn: menuBarManager.bindings.autoRehide) {
            Text("Automatically rehide")
        }
        if menuBarManager.autoRehide {
            if case .timed = menuBarManager.rehideStrategy {
                VStack(alignment: .trailing) {
                    rehideStrategyPicker
                    CompactSlider(
                        value: menuBarManager.bindings.rehideInterval,
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
        .buttonStyle(.custom)
        .environmentObject(AppState.shared)
}
