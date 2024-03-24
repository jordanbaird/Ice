//
//  HotkeyAction.swift
//  Ice
//

enum HotkeyAction: String, Codable, CaseIterable {
    case toggleHiddenSection = "ToggleHiddenSection"
    case toggleAlwaysHiddenSection = "ToggleAlwaysHiddenSection"
    case toggleApplicationMenus = "ToggleApplicationMenus"
    case showSectionDividers = "ShowSectionDividers"

    func perform(appState: AppState) {
        switch self {
        case .toggleHiddenSection:
            guard let section = appState.menuBarManager.section(withName: .hidden) else {
                return
            }
            section.toggle()
            // prevent the section from automatically rehiding after mouse movement
            appState.showOnHoverPreventedByUserInteraction = !section.isHidden
        case .toggleAlwaysHiddenSection:
            guard let section = appState.menuBarManager.section(withName: .alwaysHidden) else {
                return
            }
            section.toggle()
            // prevent the section from automatically rehiding after mouse movement
            appState.showOnHoverPreventedByUserInteraction = !section.isHidden
        case .toggleApplicationMenus:
            appState.menuBarManager.toggleApplicationMenus()
        case .showSectionDividers:
            appState.settingsManager.advancedSettingsManager.showSectionDividers.toggle()
        }
    }
}
