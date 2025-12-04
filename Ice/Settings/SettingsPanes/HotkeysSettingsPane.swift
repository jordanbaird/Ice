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

    private var generalSettingsManager: GeneralSettingsManager {
        appState.settingsManager.generalSettingsManager
    }

    var body: some View {
        IceForm {
            IceSection(header: {
                Text(verbatim: "Menu Bar Sections".localized(for: generalSettingsManager.language))
                    .font(.headline)
            }) {
                hotkeyRecorder(forSection: .hidden)
                hotkeyRecorder(forSection: .alwaysHidden)
            }
            IceSection(header: {
                Text(verbatim: "Menu Bar Items".localized(for: generalSettingsManager.language))
                    .font(.headline)
            }) {
                hotkeyRecorder(forAction: .searchMenuBarItems)
            }
            IceSection(header: {
                Text(verbatim: "Other".localized(for: generalSettingsManager.language))
                    .font(.headline)
            }) {
                hotkeyRecorder(forAction: .enableIceBar)
                hotkeyRecorder(forAction: .showSectionDividers)
                hotkeyRecorder(forAction: .toggleApplicationMenus)
            }
        }
    }

    @ViewBuilder
    private func hotkeyRecorder(forAction action: HotkeyAction) -> some View {
        if let hotkey = hotkeySettingsManager.hotkey(withAction: action) {
            HotkeyRecorder(hotkey: hotkey) {
                switch action {
                case .toggleHiddenSection:
                    Text(verbatim: "Toggle the hidden section".localized(for: generalSettingsManager.language))
                case .toggleAlwaysHiddenSection:
                    Text(verbatim: "Toggle the always-hidden section".localized(for: generalSettingsManager.language))
                case .searchMenuBarItems:
                    Text(verbatim: "Search menu bar items".localized(for: generalSettingsManager.language))
                case .enableIceBar:
                    Text(verbatim: "Enable the Ice Bar".localized(for: generalSettingsManager.language))
                case .showSectionDividers:
                    Text(verbatim: "Show section dividers".localized(for: generalSettingsManager.language))
                case .toggleApplicationMenus:
                    Text(verbatim: "Toggle application menus".localized(for: generalSettingsManager.language))
                }
            }
        }
    }

    @ViewBuilder
    private func hotkeyRecorder(forSection name: MenuBarSection.Name) -> some View {
        if appState.menuBarManager.section(withName: name)?.isEnabled == true {
            if case .hidden = name {
                hotkeyRecorder(forAction: .toggleHiddenSection)
            } else if case .alwaysHidden = name {
                hotkeyRecorder(forAction: .toggleAlwaysHiddenSection)
            }
        }
    }
}
