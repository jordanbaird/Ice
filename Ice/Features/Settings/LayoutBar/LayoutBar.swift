//
//  LayoutBar.swift
//  Ice
//

import SwiftUI

/// A view that manages the layout of menu bar items.
struct LayoutBar: View {
    private struct Representable: NSViewRepresentable {
        @ObservedObject var appState: AppState
        @ObservedObject var section: MenuBarSection

        let spacing: CGFloat

        func makeNSView(context: Context) -> LayoutBarScrollView {
            LayoutBarScrollView(
                spacing: spacing,
                arrangedViews: makeArrangedViews()
            )
        }

        func updateNSView(_ nsView: LayoutBarScrollView, context: Context) {
            nsView.arrangedViews = makeArrangedViews()
        }

        func makeArrangedViews() -> [LayoutBarItemView] {
            lazy var content = SharedContent.current
            switch section.name {
            case .visible:
                let disabledDisplayNames = [
                    "Clock",
                    "Siri",
                    "Control Center",
                ]
                return appState.itemManager.visibleItems.compactMap { item in
                    guard let image = item.captureImage(with: content) else {
                        return nil
                    }
                    return LayoutBarItemView(
                        image: image,
                        size: item.frame.size,
                        toolTip: item.displayName,
                        isEnabled: !disabledDisplayNames.contains(item.displayName)
                    )
                }
            case .hidden:
                return appState.itemManager.hiddenItems.compactMap { item in
                    guard let image = item.captureImage(with: content) else {
                        return nil
                    }
                    return LayoutBarItemView(
                        image: image,
                        size: item.frame.size,
                        toolTip: item.displayName,
                        isEnabled: true
                    )
                }
            case .alwaysHidden:
                return appState.itemManager.alwaysHiddenItems.compactMap { item in
                    guard let image = item.captureImage(with: content) else {
                        return nil
                    }
                    return LayoutBarItemView(
                        image: image,
                        size: item.frame.size,
                        toolTip: item.displayName,
                        isEnabled: true
                    )
                }
            }
        }
    }

    @AppStorage(Defaults.usesLayoutBarDecorations) var usesLayoutBarDecorations = true
    @ObservedObject var appState: AppState
    @ObservedObject var section: MenuBarSection

    /// The amount of spacing between each layout item.
    let spacing: CGFloat

    /// Creates a layout bar with the given spacing, app state, and
    /// menu bar section.
    ///
    /// - Parameters:
    ///   - spacing: The amount of spacing between each layout item.
    ///   - appState: The shared app state.
    ///   - section: The menu bar section whose items should be displayed.
    init(
        spacing: CGFloat = 0,
        appState: AppState,
        section: MenuBarSection
    ) {
        self.spacing = spacing
        self.appState = appState
        self.section = section
    }

    var body: some View {
        if usesLayoutBarDecorations {
            Representable(
                appState: appState,
                section: section,
                spacing: spacing
            )
            .background {
                backgroundView
            }
            .overlay {
                tintView
            }
            .overlay {
                borderView
            }
            .shadow(
                color: Color(
                    white: 0,
                    opacity: appState.menuBar.hasShadow ? 0.2 : 0
                ),
                radius: 5
            )
        } else {
            Representable(
                appState: appState,
                section: section,
                spacing: spacing
            )
            .background {
                RoundedRectangle(cornerRadius: 9)
                    .fill(.defaultLayoutBar)
            }
        }
    }

    @ViewBuilder
    private var backgroundView: some View {
        if let averageColor = appState.menuBar.averageColor {
            Color(cgColor: averageColor)
                .overlay(
                    Material.bar
                        .opacity(0.2)
                        .blendMode(.multiply)
                )
                .clipShape(RoundedRectangle(cornerRadius: 9))
        }
    }

    @ViewBuilder
    private var tintView: some View {
        switch appState.menuBar.tintKind {
        case .none:
            EmptyView()
        case .solid:
            RoundedRectangle(cornerRadius: 9)
                .fill(Color(cgColor: appState.menuBar.tintColor))
                .opacity(0.2)
                .allowsHitTesting(false)
        case .gradient:
            appState.menuBar.tintGradient
                .clipShape(RoundedRectangle(cornerRadius: 9))
                .opacity(0.2)
                .allowsHitTesting(false)
        }
    }

    @ViewBuilder
    private var borderView: some View {
        if appState.menuBar.hasBorder {
            RoundedRectangle(cornerRadius: 9)
                .inset(by: -appState.menuBar.borderWidth / 2)
                .stroke(
                    Color(cgColor: appState.menuBar.borderColor),
                    lineWidth: appState.menuBar.borderWidth
                )
        }
    }
}

#if DEBUG
private struct PreviewLayoutBar: View {
    @StateObject private var appState = AppState.shared

    var body: some View {
        if let section = appState.menuBar.section(withName: .visible) {
            LayoutBar(
                spacing: 5,
                appState: appState,
                section: section
            )
        }
    }
}

#Preview {
    VStack {
        PreviewLayoutBar()
        PreviewLayoutBar()
        PreviewLayoutBar()
    }
    .padding()
}
#endif
