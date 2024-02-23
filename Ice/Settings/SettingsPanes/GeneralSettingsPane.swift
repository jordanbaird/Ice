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

    var body: some View {
        Form {
            Section {
                launchAtLogin
            }
            Section {
                alwaysHiddenOptions
            }
            Section {
                showOnHover
            }
            Section {
                autoRehideOptions
            }
            Section {
                iceIconOptions
            }
            Section("Hotkeys") {
                hiddenRecorder
                alwaysHiddenRecorder
            }
        }
        .formStyle(.grouped)
        .scrollContentBackground(.hidden)
        .scrollBounceBehavior(.basedOnSize)
        .frame(maxHeight: .infinity)
        .errorOverlay(for: HotkeyRecordingFailure.self)
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
    private var showOnHover: some View {
        Toggle(isOn: menuBarManager.bindings.showOnHover) {
            Text("Show on hover")
            Text("Hover over an empty area in the menu bar to show hidden items")
        }
    }

    @ViewBuilder
    private var autoRehideOptions: some View {
        Toggle(isOn: menuBarManager.bindings.autoRehide) {
            Text("Automatically rehide")
            Text("Rehide menu bar items after a fixed amount of time, or when the focused app changes")
        }
        if menuBarManager.autoRehide {
            Picker("Rehide rule", selection: menuBarManager.bindings.rehideRule) {
                ForEach(RehideRule.allCases) { rule in
                    Text(rule.localized).tag(rule)
                }
            }
            if case .timed = menuBarManager.rehideRule {
                HStack {
                    Text("Rehide interval")
                    CompactSlider(
                        value: menuBarManager.bindings.rehideInterval,
                        in: 0...30,
                        step: 1,
                        handleVisibility: .hovering(width: 1)
                    ) {
                        if menuBarManager.rehideInterval == 1 {
                            Text("\(menuBarManager.rehideInterval.formatted()) second")
                        } else {
                            Text("\(menuBarManager.rehideInterval.formatted()) seconds")
                        }
                    }
                }
            }
        }
    }

    @ViewBuilder
    private var alwaysHiddenOptions: some View {
        if let section = menuBarManager.section(withName: .alwaysHidden) {
            Toggle(isOn: section.bindings.isEnabled) {
                Text("Enable \"\(section.name.rawValue)\" section")
                if section.isEnabled {
                    Text("\(menuBarManager.secondaryActionModifier.label) (\(menuBarManager.secondaryActionModifier.stringValue)) + click either of \(Constants.appName)'s menu bar items to temporarily show this section")
                }
            }

            if section.isEnabled {
                Picker("Modifier", selection: menuBarManager.bindings.secondaryActionModifier) {
                    ForEach(ControlItem.secondaryActionModifiers, id: \.self) { modifier in
                        Text("\(modifier.stringValue) \(modifier.label)").tag(modifier)
                    }
                }
            }
        }
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
    private func hotkeyRecorder(for section: MenuBarSection) -> some View {
        if section.isEnabled {
            HotkeyRecorder(section: section) {
                Text("Toggle the \"\(section.name.rawValue)\" menu bar section")
            }
        }
    }

    @ViewBuilder
    private var hiddenRecorder: some View {
        if let section = menuBarManager.section(withName: .hidden) {
            hotkeyRecorder(for: section)
        }
    }

    @ViewBuilder
    private var alwaysHiddenRecorder: some View {
        if let section = menuBarManager.section(withName: .alwaysHidden) {
            hotkeyRecorder(for: section)
        }
    }
}

#Preview {
    GeneralSettingsPane()
        .fixedSize()
        .buttonStyle(.custom)
        .environmentObject(AppState.shared)
}
