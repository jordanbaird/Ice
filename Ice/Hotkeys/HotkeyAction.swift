//
//  HotkeyAction.swift
//  Ice
//

enum HotkeyAction: String, Codable, CaseIterable {
    // Menu Bar Sections
    case toggleHiddenSection = "ToggleHiddenSection"
    case toggleAlwaysHiddenSection = "ToggleAlwaysHiddenSection"

    // Menu Bar Items
    case searchMenuBarItems = "SearchMenuBarItems"

    // Other
    case enableIceBar = "EnableIceBar"
    case showSectionDividers = "ShowSectionDividers"
    case toggleApplicationMenus = "ToggleApplicationMenus"

    @MainActor
    func perform(appState: AppState) async {
        switch self {
        case .toggleHiddenSection:
            guard let section = appState.menuBarManager.section(withName: .hidden) else {
                return
            }
            section.toggle()
            // Prevent the section from automatically rehiding after mouse movement.
            if !section.isHidden {
                appState.preventShowOnHover()
            }
        case .toggleAlwaysHiddenSection:
            guard let section = appState.menuBarManager.section(withName: .alwaysHidden) else {
                return
            }
            section.toggle()
            // Prevent the section from automatically rehiding after mouse movement.
            if !section.isHidden {
                appState.preventShowOnHover()
            }
        case .searchMenuBarItems:
            await appState.menuBarManager.searchPanel.toggle()
        case .enableIceBar:
            // Toggle Ice Bar on the current display (where mouse is, or main display)
            let targetScreen = NSScreen.screenWithMouse ?? NSScreen.main
            if let targetScreen {
                let displayManager = appState.settingsManager.displaySettingsManager
                let currentConfig = displayManager.configuration(for: targetScreen.displayID)
                var newConfig = currentConfig
                newConfig.useIceBar.toggle()
                displayManager.setConfiguration(newConfig, for: targetScreen.displayID)
            }
        case .showSectionDividers:
            appState.settingsManager.advancedSettingsManager.showSectionDividers.toggle()
        case .toggleApplicationMenus:
            appState.menuBarManager.toggleApplicationMenus()
        }
    }
}
