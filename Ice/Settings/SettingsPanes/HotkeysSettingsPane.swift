//
//  HotkeysSettingsPane.swift
//  Ice
//

import SwiftUI

struct HotkeysSettingsPane: View {
    @EnvironmentObject var appState: AppState

    private var hotkeySettingsManager: HotkeySettingsManager {
        appState.settingsManager.hotkeySettingsManager
    }

    var body: some View {
        Form {
            Section("Menu Bar Sections") {
                hotkeyRecorder(forAction: .toggleHiddenSection)
                hotkeyRecorder(forAction: .toggleAlwaysHiddenSection)
            }
            Section("Other") {
                hotkeyRecorder(forAction: .toggleApplicationMenus)
                hotkeyRecorder(forAction: .showSectionDividers)
            }
        }
        .formStyle(.grouped)
        .scrollContentBackground(.hidden)
        .scrollBounceBehavior(.basedOnSize)
        .frame(maxHeight: .infinity)
        .errorOverlay(for: HotkeyRecordingFailure.self)
    }

    @ViewBuilder
    private func hotkeyRecorder(forAction action: HotkeyAction) -> some View {
        if let hotkey = hotkeySettingsManager.hotkey(withAction: action) {
            HotkeyRecorder(hotkey: hotkey) {
                switch action {
                case .toggleHiddenSection:
                    Text("Toggle the hidden section")
                case .toggleAlwaysHiddenSection:
                    Text("Toggle the always-hidden section")
                case .toggleApplicationMenus:
                    Text("Toggle application menus")
                case .showSectionDividers:
                    Text("Show section dividers")
                }
            }
        }
    }
}
