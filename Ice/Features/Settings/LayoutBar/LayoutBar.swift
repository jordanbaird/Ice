//
//  LayoutBar.swift
//  Ice
//

import SwiftUI

/// A view that manages the layout of menu bar items.
struct LayoutBar: View {
    private struct Representable: NSViewRepresentable {
        @State private var cachedViews = [Int: LayoutBarItemView]()
        @Binding var layoutItems: [LayoutBarItem]
        let spacing: CGFloat

        func makeNSView(context: Context) -> LayoutBarScrollView {
            LayoutBarScrollView(
                spacing: spacing,
                arrangedViews: views(from: layoutItems)
            )
        }

        func updateNSView(
            _ nsView: LayoutBarScrollView,
            context: Context
        ) {
            nsView.arrangedViews = views(from: layoutItems)
        }

        func views(from layoutItems: [LayoutBarItem]) -> [LayoutBarItemView] {
            var views = [LayoutBarItemView]()
            for layoutItem in layoutItems {
                if let view = cachedViews[layoutItem.id] {
                    views.append(view)
                } else {
                    let view = layoutItem.makeItemView()
                    DispatchQueue.main.async {
                        cachedViews[layoutItem.id] = view
                    }
                    views.append(view)
                }
            }
            return views
        }
    }

    @EnvironmentObject var styleReader: LayoutBarStyleReader

    /// The items displayed in the layout bar.
    @Binding var layoutItems: [LayoutBarItem]

    /// The amount of spacing between each layout item.
    let spacing: CGFloat
    
    /// Creates a layout bar with the given spacing and layout items.
    ///
    /// - Parameters:
    ///   - spacing: The amount of spacing between each layout item.
    ///   - layoutItems: The items displayed in the layout bar.
    init(
        spacing: CGFloat = 0,
        layoutItems: Binding<[LayoutBarItem]>
    ) {
        self.spacing = spacing
        self._layoutItems = layoutItems
    }

    var body: some View {
        Representable(
            layoutItems: $layoutItems,
            spacing: spacing
        )
        .background {
            RoundedRectangle(cornerRadius: 9)
                .fill(styleReader.style)
        }
    }
}

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

    var body: some View {
        LayoutBar(
            spacing: 5,
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
    let styleReader = LayoutBarStyleReader(windowList: .shared)

    return VStack {
        PreviewLayoutBar()
        PreviewLayoutBar()
        PreviewLayoutBar()
    }
    .padding()
    .environmentObject(styleReader)
}
