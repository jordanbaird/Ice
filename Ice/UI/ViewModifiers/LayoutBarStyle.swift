//
//  LayoutBarStyle.swift
//  Ice
//

import SwiftUI

extension View {
    /// Returns a view that is drawn in the style of a layout bar.
    ///
    /// - Note: The view this modifier is applied to must be transparent,
    ///   or the style will be drawn incorrectly.
    ///
    /// - Parameter appState: The shared app state.
    @MainActor
    @ViewBuilder
    func layoutBarStyle(appState: AppState) -> some View {
        background {
            if appState.isActiveSpaceFullscreen {
                Color.black
            } else if let info = appState.menuBarManager.averageColorInfo {
                switch info.source {
                case .menuBarWindow:
                    Color(cgColor: info.color)
                        .overlay(
                            Material.bar
                                .opacity(0.2)
                                .blendMode(.softLight)
                        )
                case .desktopWallpaper:
                    Color(cgColor: info.color)
                        .overlay(
                            Material.bar
                                .opacity(0.5)
                                .blendMode(.softLight)
                        )
                }
            } else {
                Color.defaultLayoutBar
            }
        }
        .overlay {
            if !appState.isActiveSpaceFullscreen {
                switch appState.menuBarManager.appearanceManager.configuration.tintKind {
                case .none:
                    EmptyView()
                case .solid:
                    Color(cgColor: appState.menuBarManager.appearanceManager.configuration.tintColor)
                        .opacity(0.2)
                        .allowsHitTesting(false)
                case .gradient:
                    appState.menuBarManager.appearanceManager.configuration.tintGradient
                        .opacity(0.2)
                        .allowsHitTesting(false)
                }
            }
        }
    }
}
