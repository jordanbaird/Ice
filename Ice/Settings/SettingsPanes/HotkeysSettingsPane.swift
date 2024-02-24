//
//  HotkeysSettingsPane.swift
//  Ice
//

import SwiftUI

struct HotkeysSettingsPane: View {
    @EnvironmentObject var appState: AppState

    private var menuBarManager: MenuBarManager {
        appState.menuBarManager
    }

    var body: some View {
        Form {
            Section {
                hiddenRecorder
                alwaysHiddenRecorder
            }
        }
        .formStyle(.grouped)
        .scrollContentBackground(.hidden)
        .scrollBounceBehavior(.basedOnSize)
        .frame(maxHeight: .infinity)
        .errorOverlay(for: HotkeyRecordingFailure.self)
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
