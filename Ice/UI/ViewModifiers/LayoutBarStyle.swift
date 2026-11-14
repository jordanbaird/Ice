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
    func layoutBarStyle(appState: AppState, averageColorInfo: MenuBarAverageColorInfo?, tintOpacity: Double = 0.2, useLiveBlur: Bool = false) -> some View {
        background {
            if appState.isActiveSpaceFullscreen {
                Color.black
            } else if useLiveBlur {
                // Mirror MenuBarOverlayPanel.updateChrome: live .menu blur
                // under the tint instead of a static average-color sample —
                // the bar sits on the wallpaper so only live blur matches
                // the split pill.
                let current = appState.appearanceManager.configuration.current
                if !(current.blurAmount <= 0 || (current.tintKind != .none && current.tintOpacity >= 1)) {
                    VisualEffectView(material: .menu, blendingMode: .behindWindow)
                        .opacity(current.blurAmount)
                }
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
                        .opacity(tintOpacity)
                        .allowsHitTesting(false)
                case .gradient:
                    appState.appearanceManager.configuration.current.tintGradient
                        .opacity(tintOpacity)
                        .allowsHitTesting(false)
                }
            }
        }
    }
}
