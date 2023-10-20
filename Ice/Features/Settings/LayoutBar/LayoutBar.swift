//
//  LayoutBar.swift
//  Ice
//

import SwiftUI

/// A view that manages the layout of menu bar items.
struct LayoutBar: View {
    private struct Representable: NSViewRepresentable {
        @Binding var layoutItems: [LayoutBarItem]

        let spacing: CGFloat

        func makeNSView(context: Context) -> LayoutBarScrollView {
            LayoutBarScrollView(
                spacing: spacing,
                arrangedViews: layoutItems.map { $0.view }
            )
        }

        func updateNSView(_ nsView: LayoutBarScrollView, context: Context) {
            nsView.arrangedViews = layoutItems.map { $0.view }
        }
    }

    @Binding var layoutItems: [LayoutBarItem]
    @ObservedObject var appearanceManager: MenuBarAppearanceManager

    /// The amount of spacing between each layout item.
    let spacing: CGFloat

    /// The color of the layout bar's background.
    var backgroundColor: Color? {
        guard let averageColor = appearanceManager.averageColor else {
            return nil
        }
        return Color(cgColor: averageColor)
    }

    /// Creates a layout bar with the given spacing, appearance manager,
    /// and layout items.
    ///
    /// - Parameters:
    ///   - spacing: The amount of spacing between each layout item.
    ///   - appearanceManager: The appearance manager that manages the
    ///     menu bar, to synchronize the appearance of the layout bar.
    ///   - layoutItems: The items displayed in the layout bar.
    init(
        spacing: CGFloat = 0,
        appearanceManager: MenuBarAppearanceManager,
        layoutItems: Binding<[LayoutBarItem]>
    ) {
        self._layoutItems = layoutItems
        self.spacing = spacing
        self.appearanceManager = appearanceManager
    }

    var body: some View {
        Representable(
            layoutItems: $layoutItems,
            spacing: spacing
        )
        .background {
            if let backgroundColor {
                backgroundColor
                    .overlay(
                        Material.bar
                            .opacity(0.2)
                            .blendMode(.multiply)
                    )
                    .clipShape(
                        RoundedRectangle(cornerRadius: 9)
                    )
            } else {
                RoundedRectangle(cornerRadius: 9)
                    .fill(.defaultLayoutBar)
            }
        }
        .overlay {
            if backgroundColor != nil {
                switch appearanceManager.tintKind {
                case .none:
                    EmptyView()
                case .solid:
                    if let tintColor = appearanceManager.tintColor {
                        RoundedRectangle(cornerRadius: 9)
                            .fill(Color(cgColor: tintColor))
                            .opacity(0.2)
                            .allowsHitTesting(false)
                    }
                case .gradient:
                    if let tintGradient = appearanceManager.tintGradient {
                        tintGradient
                            .clipShape(RoundedRectangle(cornerRadius: 9))
                            .opacity(0.2)
                            .allowsHitTesting(false)
                    }
                }
            }
        }
    }
}

#if DEBUG
private struct PreviewLayoutBar: View {
    @State private var layoutItems = [
        LayoutBarItem(
            image: badge("0"),
            toolTip: "0",
            isEnabled: true
        ),
        LayoutBarItem(
            image: badge("1"),
            toolTip: "1",
            isEnabled: true
        ),
        LayoutBarItem(
            image: badge("2"),
            toolTip: "2",
            isEnabled: true
        ),
        LayoutBarItem(
            image: badge("3"),
            toolTip: "3",
            isEnabled: true
        ),
        LayoutBarItem(
            image: badge("4"),
            toolTip: "4",
            isEnabled: true
        ),
    ]

    @StateObject private var appearanceManager = MenuBarAppearanceManager(menuBarManager: MenuBarManager())

    var body: some View {
        LayoutBar(
            spacing: 5,
            appearanceManager: appearanceManager,
            layoutItems: $layoutItems
        )
    }

    static func badge(_ string: String) -> NSImage {
        NSImage(
            size: CGSize(width: 20, height: 20),
            flipped: false
        ) { bounds in
            let attributes: [NSAttributedString.Key: Any] = [
                .foregroundColor: NSColor.black,
                .font: NSFont.systemFont(ofSize: 12),
            ]
            let string = string as NSString
            let size = string.size(withAttributes: attributes)
            let point = CGPoint(
                x: bounds.midX - size.width / 2,
                y: bounds.midY - size.height / 2
            )

            NSColor.white.setFill()
            NSBezierPath(ovalIn: bounds).fill()
            string.draw(at: point, withAttributes: attributes)
            return true
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
