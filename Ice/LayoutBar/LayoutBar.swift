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

    private var menuBarManager: MenuBarManager {
        appState.menuBarManager
    }

    private var appearanceManager: MenuBarAppearanceManager {
        menuBarManager.appearanceManager
    }

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
        .background {
            backgroundView
        }
        .overlay {
            tintView
        }
        .clipShape(
            RoundedRectangle(cornerRadius: 9)
        )
    }

    @ViewBuilder
    private var backgroundView: some View {
        if let averageColor = menuBarManager.averageColor {
            Color(cgColor: averageColor)
                .overlay(
                    Material.bar
                        .opacity(0.5)
                        .blendMode(.softLight)
                )
        } else {
            Color.defaultLayoutBar
        }
    }

    @ViewBuilder
    private var tintView: some View {
        switch appearanceManager.configuration.tintKind {
        case .none:
            EmptyView()
        case .solid:
            Color(cgColor: appearanceManager.configuration.tintColor)
                .opacity(0.2)
                .allowsHitTesting(false)
        case .gradient:
            appearanceManager.configuration.tintGradient
                .opacity(0.2)
                .allowsHitTesting(false)
        }
    }
}
