//
//  GeneralSettingsPane.swift
//  Ice
//

import SwiftUI

struct GeneralSettingsPane: View {
    @EnvironmentObject var statusBar: StatusBar
    @State private var failureReason: HotkeyRecorder.FailureReason?

    private var failureOverlayIsVisible: Binding<Bool> {
        Binding(
            get: { failureReason != nil },
            set: { failureReason = $0 ? failureReason : nil }
        )
    }

    var body: some View {
        ZStack {
            settingsPaneBody
            OverlayView(isVisible: failureOverlayIsVisible) {
                Text(failureReason?.message ?? "")
                    .font(.system(size: 18, weight: .light))
                    .padding()
            }
        }
        .onChange(of: statusBar.section(withName: .alwaysHidden)?.isEnabled) { newValue in
            let isEnabled = newValue ?? false
            guard let section = statusBar.section(withName: .alwaysHidden) else {
                return
            }
            section.controlItem.isVisible = isEnabled
            if isEnabled {
                section.enableHotkey()
            } else {
                section.disableHotkey()
            }
        }
        .padding()
    }

    var settingsPaneBody: some View {
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
                isOn: Binding(
                    get: { statusBar.section(withName: .alwaysHidden)?.isEnabled ?? false },
                    set: { statusBar.section(withName: .alwaysHidden)?.isEnabled = $0 }
                )
            )
        }
        .padding()
    }

    var hotkeyStack: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text("Hotkeys")
                .font(.system(size: 20, weight: .light))

            Grid {
                LabeledHotkeyRecorder(
                    sectionName: .hidden,
                    failureReason: $failureReason
                )
                LabeledHotkeyRecorder(
                    sectionName: .alwaysHidden,
                    failureReason: $failureReason
                )
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

struct LabeledHotkeyRecorder: View {
    typealias FailureReason = HotkeyRecorder.FailureReason

    @EnvironmentObject var statusBar: StatusBar

    @Binding var failureReason: FailureReason?

    @State private var timer: Timer?

    let sectionName: StatusBarSection.Name

    init(sectionName: StatusBarSection.Name, failureReason: Binding<FailureReason?>) {
        self.sectionName = sectionName
        self._failureReason = failureReason
    }

    var body: some View {
        conditionalGridRow
            .onChange(of: failureReason) { newValue in
                if newValue == nil {
                    timer?.invalidate()
                }
            }
    }

    @ViewBuilder
    private var conditionalGridRow: some View {
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

            HotkeyRecorder(section: statusBar.section(withName: sectionName)) { reason in
                failureReason = reason
                timer?.invalidate()
                timer = Timer.scheduledTimer(withTimeInterval: 3, repeats: false) { _ in
                    failureReason = nil
                }
            } removeFailureWarning: {
                timer?.invalidate()
                // FIXME: Failure warning shouldn't animate out when force removing,
                // but withAnimation(nil) { ... } doesn't seem to work for this
                failureReason = nil
            }
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
