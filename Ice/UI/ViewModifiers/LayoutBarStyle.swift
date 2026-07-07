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
                let current = appState.appearanceManager.configuration.current
                switch current.appearanceKind {
                case .none:
                    EmptyView()
                case .tint:
                    // Fixed 20% overlay, regardless of stored alpha.
                    switch current.tintKind {
                    case .none:
                        EmptyView()
                    case .solid:
                        Color(cgColor: current.tintColor.copy(alpha: 1) ?? current.tintColor)
                            .opacity(0.2)
                            .allowsHitTesting(false)
                    case .gradient:
                        current.tintGradient.withAlphaComponent(0.2)
                            .allowsHitTesting(false)
                    }
                case .backdrop:
                    // Honor the stored alpha (user-controllable, default 100%).
                    switch current.tintKind {
                    case .none:
                        EmptyView()
                    case .solid:
                        Color(cgColor: current.tintColor)
                            .allowsHitTesting(false)
                    case .gradient:
                        current.tintGradient
                            .allowsHitTesting(false)
                    }
                }
            }
        }
    }
}
