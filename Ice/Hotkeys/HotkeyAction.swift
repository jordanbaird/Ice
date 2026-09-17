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

    var isAvailable: Bool {
        if #available(macOS 27.0, *) {
            return self == .toggleHiddenSection || self == .toggleAlwaysHiddenSection
        }
        return true
    }

    @MainActor
    func perform(appState: AppState) {
        guard isAvailable else { return }
        switch self {
        case .toggleHiddenSection:
            guard let section = appState.menuBarManager.section(withName: .hidden) else {
                return
            }
            appState.menuBarManager.prepareForControlToggle()
            section.toggle()
            // Prevent the section from automatically rehiding after mouse movement.
            if !section.isHidden {
                appState.menuBarManager.showOnHoverAllowed = false
            }
        case .toggleAlwaysHiddenSection:
            guard let section = appState.menuBarManager.section(withName: .alwaysHidden) else {
                return
            }
            appState.menuBarManager.prepareForControlToggle()
            section.toggle()
            // Prevent the section from automatically rehiding after mouse movement.
            if !section.isHidden {
                appState.menuBarManager.showOnHoverAllowed = false
            }
        case .searchMenuBarItems:
            appState.menuBarManager.searchPanel.toggle()
        case .enableIceBar:
            appState.settings.general.useIceBar.toggle()
        case .toggleApplicationMenus:
            appState.menuBarManager.toggleApplicationMenus()
        }
    }
}
