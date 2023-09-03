//
//  GeneralSettingsPane.swift
//  Ice
//

import SwiftKeys
import SwiftUI

struct GeneralSettingsPane: View {
    @EnvironmentObject var statusBar: StatusBar

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
            .mask(scrollViewMask)

            VStack(alignment: .leading, spacing: 20) {
                Divider()
                footerView
            }
        }
        .onChange(of: statusBar.section(withName: .alwaysHidden)?.isEnabled) { newValue in
            let isEnabled = newValue ?? false
            guard let section = statusBar.section(withName: .alwaysHidden) else {
                return
            }
            section.controlItem.isVisible = isEnabled
            if isEnabled {
                KeyCommand(name: .toggle(section: section)).enable()
            } else {
                KeyCommand(name: .toggle(section: section)).disable()
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
                isOn: $statusBar.isAlwaysHiddenSectionEnabled
            )
        }
        .padding()
    }

    var hotkeyStack: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text("Hotkeys")
                .font(.system(size: 20, weight: .light))

            Grid {
                LabeledKeyRecorder(sectionName: .hidden)
                LabeledKeyRecorder(sectionName: .alwaysHidden)
            }
        }
        .padding()
    }

    var scrollViewMask: some View {
        VStack(spacing: 0) {
            LinearGradient(
                colors: [.clear, .black],
                startPoint: .top,
                endPoint: .bottom
            )
            .frame(height: 10)

            Rectangle().fill(.black)

            LinearGradient(
                colors: [.black, .clear],
                startPoint: .top,
                endPoint: .bottom
            )
            .frame(height: 10)
        }
    }
}

struct LabeledKeyRecorder: View {
    @EnvironmentObject var statusBar: StatusBar

    let sectionName: StatusBarSection.Name

    var keyCommandName: KeyCommand.Name? {
        guard let section = statusBar.section(withName: sectionName) else {
            return nil
        }
        return .toggle(section: section)
    }

    var body: some View {
        if
            let section = statusBar.section(withName: sectionName),
            statusBar.isSectionEnabled(section)
        {
            gridRow
        } else {
            gridRow
                .frame(height: 0)
                .hidden()
        }
    }

    private var gridRow: some View {
        GridRow {
            Text("Toggle the \"\(sectionName.rawValue)\" menu bar section")
            KeyRecorder(name: keyCommandName)
        }
        .gridColumnAlignment(.leading)
    }
}

struct GeneralSettingsPane_Previews: PreviewProvider {
    @StateObject private static var statusBar = StatusBar()

    static var previews: some View {
        GeneralSettingsPane()
            .fixedSize()
            .buttonStyle(SettingsButtonStyle())
            .toggleStyle(SettingsToggleStyle())
            .environmentObject(statusBar)
    }
}
