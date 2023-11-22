//
//  GeneralSettingsPane.swift
//  Ice
//

import LaunchAtLogin
import SwiftUI
import OSLog

struct GeneralSettingsPane: View {
    @AppStorage(Defaults.secondaryActionModifier) var secondaryActionModifier = Hotkey.Modifiers.option
    @EnvironmentObject var appState: AppState
    @State private var isImporting = false

    private var menuBar: MenuBar {
        appState.menuBar
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
        .errorOverlay(HotkeyRecorder.Failure.self)
        .bottomBar {
            HStack {
                Spacer()
                Button("Quit \(Constants.appName)") {
                    NSApp.terminate(nil)
                }
            }
            .padding()
        }
    }

    @ViewBuilder
    private var launchAtLogin: some View {
        LaunchAtLogin.Toggle()
    }

    @ViewBuilder
    private var alwaysHiddenOptions: some View {
        if let section = menuBar.section(withName: .alwaysHidden) {
            Toggle(isOn: section.bindings.isEnabled) {
                Text("Enable \"\(section.name.rawValue)\" section")
            }

            if section.isEnabled {
                Picker(selection: $secondaryActionModifier) {
                    ForEach(ControlItem.secondaryActionModifiers, id: \.self) { modifier in
                        Text("\(modifier.stringValue) \(modifier.label)").tag(modifier)
                    }
                } label: {
                    Text("Modifier")
                    Text("\(secondaryActionModifier.label) (\(secondaryActionModifier.stringValue)) + clicking either of \(Constants.appName)'s menu bar items will temporarily show this section")
                }
            }
        }
    }

    @ViewBuilder
    private func label(for imageSet: ControlItemImageSet) -> some View {
        Label {
            Text(imageSet.name.rawValue)
        } icon: {
            if let nsImage = imageSet.hidden.nsImage(for: menuBar) {
                Image(nsImage: nsImage)
            }
        }
        .tag(imageSet)
    }

    @ViewBuilder
    private var iceIconOptions: some View {
        LabeledContent("Ice Icon") {
            Menu {
                Picker("Ice Icon", selection: menuBar.bindings.iceIcon) {
                    ForEach(ControlItemImageSet.userSelectableImageSets) { imageSet in
                        label(for: imageSet)
                    }

                    if let lastCustomIceIcon = menuBar.lastCustomIceIcon {
                        label(for: lastCustomIceIcon)
                    }
                }
                .pickerStyle(.inline)
                .labelsHidden()

                Button("Choose Image…") {
                    isImporting = true
                }
            } label: {
                label(for: menuBar.iceIcon)
            }
            .labelStyle(.titleAndIcon)
            .scaledToFit()
            .fixedSize()
        }
        .fileImporter(isPresented: $isImporting, allowedContentTypes: [.image]) { result in
            switch result {
            case .success(let url):
                if url.startAccessingSecurityScopedResource() {
                    defer {
                        url.stopAccessingSecurityScopedResource()
                    }
                    do {
                        let data = try Data(contentsOf: url)
                        menuBar.iceIcon = ControlItemImageSet(
                            name: .custom,
                            hidden: .data(data),
                            visible: .data(data)
                        )
                    } catch {
                        Logger.general.error("Error loading icon: \(error)")
                    }
                }
            case .failure(let error):
                Logger.general.error("Error loading icon: \(error)")
            }
        }

        if case .custom = menuBar.iceIcon.name {
            Toggle(isOn: menuBar.bindings.customIceIconIsTemplate) {
                Text("Use template image")
                if menuBar.customIceIconIsTemplate {
                    Text("The icon is displayed as a monochrome image matching the system appearance")
                } else {
                    Text("The icon is displayed with its original appearance")
                }
            }
        }
    }

    @ViewBuilder
    private var hiddenRecorder: some View {
        if let section = menuBar.section(withName: .hidden) {
            LabeledHotkeyRecorder(section: section)
        }
    }

    @ViewBuilder
    private var alwaysHiddenRecorder: some View {
        if let section = menuBar.section(withName: .alwaysHidden) {
            LabeledHotkeyRecorder(section: section)
        }
    }
}

struct LabeledHotkeyRecorder: View {
    @State private var failure: HotkeyRecorder.Failure?
    @State private var timer: Timer?

    let section: MenuBarSection

    private var localizedLabel: LocalizedStringKey {
        "Toggle the \"\(section.name.rawValue)\" menu bar section"
    }

    var body: some View {
        if section.isEnabled {
            LabeledContent {
                HotkeyRecorder(section: section, failure: $failure)
            } label: {
                Text(localizedLabel)
            }
            .onChange(of: failure) { _, newValue in
                timer?.invalidate()
                if newValue != nil {
                    timer = .scheduledTimer(withTimeInterval: 3, repeats: false) { _ in
                        failure = nil
                    }
                }
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
