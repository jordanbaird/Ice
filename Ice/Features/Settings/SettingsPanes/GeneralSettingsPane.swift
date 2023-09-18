//
//  GeneralSettingsPane.swift
//  Ice
//

import LaunchAtLogin
import SwiftUI

struct GeneralSettingsPane: View {
    @EnvironmentObject var statusBar: StatusBar

    @AppStorage("enableToggleOnMouseEnterExit")
    var enableToggleOnMouseEnterExit = true
    @AppStorage("enableTimedRehide")
    var enableTimedRehide = false
    @AppStorage("rehideInterval")
    var rehideInterval = 10.0
    @AppStorage("enableOutsideInteractionChecks")
    var enableOutsideInteractionChecks = true

    var body: some View {
        Form {
            Section {
                launchAtLogin
            }
            Section {
                toggleOnMouseEnterExit
                timedRehideOptions
                outsideInteractionChecks
                enableAlwaysHidden
            }
            Section("Hotkeys") {
                hiddenRecorder
                alwaysHiddenRecorder
            }
        }
        .formStyle(.grouped)
        .scrollContentBackground(.hidden)
        .frame(maxHeight: .infinity)
        .errorOverlay(HotkeyRecorder.Failure.self)
        .bottomBar {
            HStack {
                Button("Reset") {
                    print("RESET")
                }
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
    private var toggleOnMouseEnterExit: some View {
        Toggle(
            "Toggle when mouse enters and exits the menu bar",
            isOn: $enableToggleOnMouseEnterExit
        )
    }

    @ViewBuilder
    private var timedRehideOptions: some View {
        Group {
            Toggle(
                "Automatically rehide menu bar items",
                isOn: $enableTimedRehide
            )

            if enableTimedRehide {
                HStack(alignment: .firstTextBaseline) {
                    Stepper(
                        value: $rehideInterval,
                        in: 0...300,
                        step: 1,
                        format: .number
                    ) {
                        Text("Rehide interval")
                        Text("Time interval to wait before rehiding")
                    }
                    Text("seconds")
                        .foregroundColor(.secondary)
                }
            }
        }
    }

    @ViewBuilder
    private var outsideInteractionChecks: some View {
        Toggle(
            "Interacting with other apps hides all menu bar items",
            isOn: $enableOutsideInteractionChecks
        )
    }

    @ViewBuilder
    private var enableAlwaysHidden: some View {
        if let section = statusBar.section(withName: .alwaysHidden) {
            Toggle(
                isOn: Binding(
                    get: { section.isEnabled },
                    set: { section.isEnabled = $0 }
                )
            ) {
                Text("Enable the \"\(section.name.rawValue)\" menu bar section")
                Text("⌥ (Option) + clicking either control item will temporarily show the section")
            }
            .onChange(of: section.isEnabled) { newValue in
                section.controlItem.isVisible = newValue
                if newValue {
                    section.enableHotkey()
                } else {
                    section.disableHotkey()
                }
            }
        }
    }

    @ViewBuilder
    private var hiddenRecorder: some View {
        LabeledHotkeyRecorder(sectionName: .hidden)
    }

    @ViewBuilder
    private var alwaysHiddenRecorder: some View {
        LabeledHotkeyRecorder(sectionName: .alwaysHidden)
    }
}

struct LabeledHotkeyRecorder: View {
    @EnvironmentObject var statusBar: StatusBar
    @State private var failure: HotkeyRecorder.Failure?
    @State private var timer: Timer?

    let sectionName: StatusBarSection.Name

    private var section: StatusBarSection? {
        statusBar.section(withName: sectionName)
    }

    private var localizedLabel: LocalizedStringKey {
        "Toggle the \"\(sectionName.rawValue)\" menu bar section"
    }

    var body: some View {
        if
            let section,
            section.isEnabled
        {
            LabeledContent {
                HotkeyRecorder(section: section, failure: $failure)
            } label: {
                Text(localizedLabel)
            }
            .onChange(of: failure) {
                timer?.invalidate()
                if $0 != nil {
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
