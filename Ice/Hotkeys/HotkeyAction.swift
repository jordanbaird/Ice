//
//  HotkeyAction.swift
//  Ice
//

enum HotkeyAction: Codable, CaseIterable {
    case toggleHiddenSection
    case toggleAlwaysHiddenSection
    case toggleApplicationMenus

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
        }
    }
}
