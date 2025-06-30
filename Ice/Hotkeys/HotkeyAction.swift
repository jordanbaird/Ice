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
    case toggleApplicationMenus = "ToggleApplicationMenus"

    @MainActor
    func perform(appState: AppState) async {
        switch self {
        case .toggleHiddenSection:
            guard let section = appState.menuBarManager.section(withName: .hidden) else {
                return
            }
            await section.toggle()
            // Prevent the section from automatically rehiding after mouse movement.
            if !section.isHidden {
                appState.menuBarManager.showOnHoverAllowed = false
            }
        case .toggleAlwaysHiddenSection:
            guard let section = appState.menuBarManager.section(withName: .alwaysHidden) else {
                return
            }
            await section.toggle()
            // Prevent the section from automatically rehiding after mouse movement.
            if !section.isHidden {
                appState.menuBarManager.showOnHoverAllowed = false
            }
        case .searchMenuBarItems:
            await appState.menuBarManager.searchPanel.toggle()
        case .enableIceBar:
            appState.settingsManager.generalSettingsManager.useIceBar.toggle()
        case .toggleApplicationMenus:
            appState.menuBarManager.toggleApplicationMenus()
        }
    }
}
