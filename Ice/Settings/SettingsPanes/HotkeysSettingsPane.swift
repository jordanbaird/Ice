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
                toggleHiddenSection
                toggleAlwaysHiddenSection
            }
        }
        .formStyle(.grouped)
        .scrollContentBackground(.hidden)
        .scrollBounceBehavior(.basedOnSize)
        .frame(maxHeight: .infinity)
        .errorOverlay(for: HotkeyRecordingFailure.self)
    }

    @ViewBuilder
    private func hotkeyRecorder(forToggling section: MenuBarSection) -> some View {
        if section.isEnabled {
            HotkeyRecorder(section: section) {
                Text("Toggle the \"\(section.name.rawValue)\" menu bar section")
            }
        }
    }

    @ViewBuilder
    private var toggleHiddenSection: some View {
        if let section = menuBarManager.section(withName: .hidden) {
            hotkeyRecorder(forToggling: section)
        }
    }

    @ViewBuilder
    private var toggleAlwaysHiddenSection: some View {
        if let section = menuBarManager.section(withName: .alwaysHidden) {
            hotkeyRecorder(forToggling: section)
        }
    }
}
