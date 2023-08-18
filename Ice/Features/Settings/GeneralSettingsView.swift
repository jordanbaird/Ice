//
//  GeneralSettingsView.swift
//  Ice
//

import SwiftKeys
import SwiftUI

struct GeneralSettingsView: View {
    @AppStorage(key: .enableAlwaysHidden)
    private var enableAlwaysHidden: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            VStack(alignment: .leading, spacing: 20) {
                headerView
                Divider()
            }

            ScrollView(.vertical) {
                VStack(alignment: .leading, spacing: 20) {
                    controlStack
                    Divider()
                    hotkeyStack
                }
            }
            .scrollBounceBehavior(.basedOnSize)

            VStack(alignment: .leading, spacing: 20) {
                Divider()
                footerView
            }
        }
        .padding()
    }

    var headerView: some View {
        HStack(spacing: 15) {
            Image("IceCube")
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(width: 50, height: 50)
                .fixedSize()

            Text("Ice - Menu Bar Manipulator")
                .font(.system(size: 30, weight: .thin))
        }
        .padding(.vertical, 10)
        .padding(.horizontal)
    }

    var footerView: some View {
        HStack {
            Button("Reset") {
                print("RESET")
            }
            Spacer()
            Button("Quit \(Constants.appName)") {
                NSApp.terminate(nil)
            }
        }
    }

    var controlStack: some View {
        VStack(alignment: .leading, spacing: 20) {
            Toggle(
                "Enable the \"Always Hidden\" menu bar section",
                isOn: $enableAlwaysHidden
            )
        }
        .padding()
    }

    var hotkeyStack: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text("Hotkeys")
                .font(.system(size: 20, weight: .thin))

            VStack(spacing: enableAlwaysHidden ? 5 : 0) {
                LabeledKeyRecorder(
                    section: .hidden,
                    enabled: true
                )
                LabeledKeyRecorder(
                    section: .alwaysHidden,
                    enabled: enableAlwaysHidden
                )
            }
            .fixedSize()
        }
        .padding()
    }
}

struct LabeledKeyRecorder: View {
    let section: StatusBar.Section
    let enabled: Bool

    var body: some View {
        if enabled {
            labeledContent
        } else {
            labeledContent
                .frame(height: 0)
                .hidden()
        }
    }

    private var labeledContent: some View {
        HStack {
            Text("Toggle the \"\(section.name)\" menu bar section")
            Spacer()
            SettingsKeyRecorder(name: .toggle(section))
        }
    }
}

struct GeneralSettingsView_Previews: PreviewProvider {
    static var previews: some View {
        GeneralSettingsView()
            .fixedSize()
            .buttonStyle(SettingsButtonStyle())
    }
}
