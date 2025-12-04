//
//  MenuBarLayoutSettingsPane.swift
//  Ice
//

import SwiftUI

struct MenuBarLayoutSettingsPane: View {
    @EnvironmentObject var appState: AppState

    var body: some View {
        if !ScreenCapture.cachedCheckPermissions() {
            missingScreenRecordingPermission
        } else if appState.menuBarManager.isMenuBarHiddenBySystemUserDefaults {
            cannotArrange
        } else {
            IceForm(alignment: .leading, spacing: 20) {
                header
                layoutBars
            }
        }
    }

    private var manager: GeneralSettingsManager {
        appState.settingsManager.generalSettingsManager
    }

    @ViewBuilder
    private var header: some View {
        Text(verbatim: "Drag to arrange your menu bar items".localized(for: manager.language))
            .font(.title2)

        IceGroupBox {
            AnnotationView(
                alignment: .center,
                font: .callout.bold()
            ) {

                Label {
                    Text(verbatim: "Tip: you can also arrange menu bar items by Command + dragging them in the menu bar".localized(for: manager.language))
                } icon: {
                    Image(systemName: "lightbulb")
                }
            }
        }
    }

    @ViewBuilder
    private var layoutBars: some View {
        VStack(spacing: 25) {
            ForEach(MenuBarSection.Name.allCases, id: \.self) { section in
                layoutBar(for: section)
            }
        }
    }

    @ViewBuilder
    private var cannotArrange: some View {
        Text(verbatim: "Ice cannot arrange menu bar items in automatically hidden menu bars".localized(for: manager.language))
            .font(.title3)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
    }

    @ViewBuilder
    private var missingScreenRecordingPermission: some View {
        VStack {
            Text(verbatim: "Menu bar layout requires screen recording permissions".localized(for: manager.language))
                .font(.title2)

            Button {
                appState.navigationState.settingsNavigationIdentifier = .advanced
            } label: {
                Text(verbatim: "Go to Advanced Settings".localized(for: manager.language))
            }
            .buttonStyle(.link)
        }
    }

    @ViewBuilder
    private func layoutBar(for section: MenuBarSection.Name) -> some View {
        if
            let section = appState.menuBarManager.section(withName: section),
            section.isEnabled
        {
            VStack(alignment: .leading, spacing: 4) {
                Text(verbatim: section.name.displayString.localized(for: manager.language) + " Section".localized(for: manager.language))
                    .font(.system(size: 14))
                    .padding(.leading, 2)

                LayoutBar(section: section)
                    .environmentObject(appState.imageCache)
            }
        }
    }
}
