//
//  GeneralSettingsPane.swift
//  Ice
//

import LaunchAtLogin
import SwiftUI

struct GeneralSettingsPane: View {
    @AppStorage(Defaults.usesColoredLayoutBars) var usesColoredLayoutBars = true
    @AppStorage(Defaults.secondaryActionModifier) var secondaryActionModifier = Hotkey.Modifiers.option
    @EnvironmentObject var appState: AppState

    private var menuBar: MenuBar {
        appState.menuBar
    }

    var body: some View {
        Form {
            Section {
                launchAtLogin
                coloredLayoutBars
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
    private var coloredLayoutBars: some View {
        Toggle(isOn: $usesColoredLayoutBars) {
            Text("Use colored layout bars")
            Text("When enabled, the bars in \(Constants.appName)'s Layout settings take on the color of the actual menu bar. Disabling this setting can improve performance.")
        }
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

#Preview {
    let appState = AppState()

    return GeneralSettingsPane()
        .fixedSize()
        .buttonStyle(.custom)
        .environmentObject(appState)
}
