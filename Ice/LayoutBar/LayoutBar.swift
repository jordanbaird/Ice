//
//  LayoutBar.swift
//  Ice
//

import SwiftUI

struct LayoutBar: View {
    private struct Representable: NSViewRepresentable {
        let itemManager: MenuBarItemManager
        let section: MenuBarSection
        let spacing: CGFloat

        func makeNSView(context: Context) -> LayoutBarScrollView {
            LayoutBarScrollView(itemManager: itemManager, section: section, spacing: spacing)
        }

        func updateNSView(_ nsView: LayoutBarScrollView, context: Context) {
            nsView.spacing = spacing
        }
    }

    @EnvironmentObject var appState: AppState

    let section: MenuBarSection
    let spacing: CGFloat

    init(section: MenuBarSection, spacing: CGFloat = 0) {
        self.section = section
        self.spacing = spacing
    }

    var body: some View {
        Representable(
            itemManager: appState.itemManager,
            section: section,
            spacing: spacing
        )
        .layoutBarStyle(
            menuBarManager: appState.menuBarManager,
            cornerRadius: 9
        )
    }
}
