//
//  GeneralSettingsPane.swift
//  Ice
//

import LaunchAtLogin
import SwiftUI

struct GeneralSettingsPane: View {
    @EnvironmentObject var statusBar: StatusBar

    @AppStorage("alwaysHiddenModifier")
    var alwaysHiddenModifier: Hotkey.Modifiers = .option

    var body: some View {
        Form {
            Section {
                launchAtLogin
            }
            Section {
                alwaysHiddenOptions
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
        if let section = statusBar.section(withName: .alwaysHidden) {
            Toggle(isOn: section.bindings.isEnabled) {
                Text("Enable \"\(section.name.rawValue)\" section")
            }
            .onChange(of: section.isEnabled) { newValue in
                section.controlItem.isVisible = newValue
                if newValue {
                    section.enableHotkey()
                } else {
                    section.disableHotkey()
                }
            }

            if section.isEnabled {
                Picker(selection: $alwaysHiddenModifier) {
                    ForEach(Hotkey.Modifiers.canonicalOrder, id: \.self) { modifier in
                        Text("\(modifier.stringValue) \(modifier.label)").tag(modifier)
                    }
                } label: {
                    Text("Modifier")
                    Text("\(alwaysHiddenModifier.label) (\(alwaysHiddenModifier.stringValue)) + clicking either of \(Constants.appName)'s menu bar items will temporarily show the section")
                }
            }
        }
    }

    @ViewBuilder
    private var hiddenRecorder: some View {
        if let section = statusBar.section(withName: .hidden) {
            LabeledHotkeyRecorder(section: section)
        }
    }

    @ViewBuilder
    private var alwaysHiddenRecorder: some View {
        if let section = statusBar.section(withName: .alwaysHidden) {
            LabeledHotkeyRecorder(section: section)
        }
    }
}

struct LabeledHotkeyRecorder: View {
    @EnvironmentObject var statusBar: StatusBar
    @State private var failure: HotkeyRecorder.Failure?
    @State private var timer: Timer?

    let section: StatusBarSection

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
            .onChange(of: failure) { newValue in
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

struct GeneralSettingsPane_Previews: PreviewProvider {
    @StateObject private static var statusBar = StatusBar()

    static var previews: some View {
        GeneralSettingsPane()
            .fixedSize()
            .buttonStyle(SettingsButtonStyle())
            .environmentObject(statusBar)
    }
}
