//
//  LayoutBar.swift
//  Ice
//

import SwiftUI

struct LayoutBar: View {
    private struct Representable: NSViewRepresentable {
        let appState: AppState
        let section: MenuBarSection
        let spacing: CGFloat

        func makeNSView(context: Context) -> LayoutBarScrollView {
            LayoutBarScrollView(appState: appState, section: section, spacing: spacing)
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
        Representable(appState: appState, section: section, spacing: spacing)
            .layoutBarStyle(appState: appState)
            .clipShape(RoundedRectangle(cornerRadius: 9, style: .circular))
    }
}
