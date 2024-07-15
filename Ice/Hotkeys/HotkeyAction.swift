//
//  HotkeyAction.swift
//  Ice
//

enum HotkeyAction: String, Codable, CaseIterable {
    case toggleHiddenSection = "ToggleHiddenSection"
    case toggleAlwaysHiddenSection = "ToggleAlwaysHiddenSection"
    case toggleApplicationMenus = "ToggleApplicationMenus"
    case showSectionDividers = "ShowSectionDividers"
    case searchMenuBarItems = "SearchMenuBarItems"

    @MainActor
    func perform(appState: AppState) async {
        switch self {
        case .toggleHiddenSection:
            guard let section = appState.menuBarManager.section(withName: .hidden) else {
                return
            }
            section.toggle()
            // prevent the section from automatically rehiding after mouse movement
            if !section.isHidden {
                appState.preventShowOnHover()
            }
        case .toggleAlwaysHiddenSection:
            guard let section = appState.menuBarManager.section(withName: .alwaysHidden) else {
                return
            }
            section.toggle()
            // prevent the section from automatically rehiding after mouse movement
            if !section.isHidden {
                appState.preventShowOnHover()
            }
        case .toggleApplicationMenus:
            appState.menuBarManager.toggleApplicationMenus()
        case .showSectionDividers:
            appState.settingsManager.advancedSettingsManager.showSectionDividers.toggle()
        case .searchMenuBarItems:
            await appState.menuBarManager.searchPanel.toggle()
        }
    }
}
