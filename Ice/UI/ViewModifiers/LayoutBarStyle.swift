//
//  LayoutBarStyle.swift
//  Ice
//

import SwiftUI

extension View {
    /// Returns a view that is drawn in the style of a layout bar.
    ///
    /// - Note: The view this modifier is applied to must be transparent, or the style
    ///   will be drawn incorrectly.
    @ViewBuilder
    func layoutBarStyle(appState: AppState, averageColorInfo: MenuBarAverageColorInfo?) -> some View {
        background {
            if appState.isActiveSpaceFullscreen {
                Color.black
            } else if let averageColorInfo {
                switch averageColorInfo.source {
                case .menuBarWindow:
                    Color(cgColor: averageColorInfo.color)
                        .overlay(
                            Material.bar
                                .opacity(0.2)
                                .blendMode(.softLight)
                        )
                case .desktopWallpaper:
                    Color(cgColor: averageColorInfo.color)
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
                switch appState.appearanceManager.configuration.current.tintKind {
                case .none:
                    EmptyView()
                case .solid:
                    Color(cgColor: appState.appearanceManager.configuration.current.tintColor)
                        .opacity(0.2)
                        .allowsHitTesting(false)
                case .gradient:
                    appState.appearanceManager.configuration.current.tintGradient
                        .opacity(0.2)
                        .allowsHitTesting(false)
                }
            }
        }
    }
}
