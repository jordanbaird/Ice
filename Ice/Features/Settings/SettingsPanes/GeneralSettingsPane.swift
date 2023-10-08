//
//  GeneralSettingsPane.swift
//  Ice
//

import LaunchAtLogin
import SwiftUI

struct GeneralSettingsPane: View {
    @EnvironmentObject var menuBar: MenuBar

    @AppStorage(Defaults.usesTintedLayoutBars) var usesTintedLayoutBars = true
    @AppStorage(Defaults.alwaysHiddenModifier) var alwaysHiddenModifier = Hotkey.Modifiers.option

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
        Toggle(isOn: $usesTintedLayoutBars) {
            Text("Use tinted layout bars")
            Text("When enabled, layout bars in the Menu Bar Layout tab are tinted to match the color of the actual menu bar. Disabling this setting can improve performance.")
        }
    }

    @ViewBuilder
    private var alwaysHiddenOptions: some View {
        if let section = menuBar.section(withName: .alwaysHidden) {
            Toggle(isOn: section.bindings.isEnabled) {
                Text("Enable \"\(section.name.rawValue)\" section")
            }

            if section.isEnabled {
                Picker(selection: $alwaysHiddenModifier) {
                    ForEach(ControlItem.clickModifiers, id: \.self) { modifier in
                        Text("\(modifier.stringValue) \(modifier.label)").tag(modifier)
                    }
                } label: {
                    Text("Modifier")
                    Text("\(alwaysHiddenModifier.label) (\(alwaysHiddenModifier.stringValue)) + clicking either of \(Constants.appName)'s menu bar items will temporarily show this section")
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
    @EnvironmentObject var menuBar: MenuBar
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

struct GeneralSettingsPane_Previews: PreviewProvider {
    @StateObject private static var menuBar = MenuBar()

    static var previews: some View {
        GeneralSettingsPane()
            .fixedSize()
            .buttonStyle(SettingsButtonStyle())
            .environmentObject(menuBar)
    }
}
