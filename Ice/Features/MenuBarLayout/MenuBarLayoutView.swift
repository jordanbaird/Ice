//
//  MenuBarLayoutView.swift
//  Ice
//

import SwiftUI

struct MenuBarLayoutView: View {
    private struct Representable: NSViewRepresentable {
        @State private var cachedViews = [Int: MenuBarLayoutItemView]()
        @Binding var layoutItems: [MenuBarLayoutItem]
        let spacing: CGFloat

        func makeNSView(context: Context) -> MenuBarLayoutCocoaView {
            MenuBarLayoutCocoaView(
                spacing: spacing,
                arrangedViews: views(from: layoutItems)
            )
        }

        func updateNSView(
            _ nsView: MenuBarLayoutCocoaView,
            context: Context
        ) {
            nsView.arrangedViews = views(from: layoutItems)
        }

        func views(from layoutItems: [MenuBarLayoutItem]) -> [MenuBarLayoutItemView] {
            var views = [MenuBarLayoutItemView]()
            for layoutItem in layoutItems {
                if let view = cachedViews[layoutItem.id] {
                    views.append(view)
                } else {
                    let view = layoutItem.makeItemView()
                    cachedViews[layoutItem.id] = view
                    views.append(view)
                }
            }
            return views
        }
    }

    @EnvironmentObject var styleReader: MenuBarStyleReader

    /// The items displayed in the layout view.
    @Binding var layoutItems: [MenuBarLayoutItem]

    /// The amount of spacing between each layout item.
    let spacing: CGFloat
    
    /// Creates a layout view with the given spacing and layout items.
    ///
    /// - Parameters:
    ///   - spacing: The amount of spacing between each layout item.
    ///   - layoutItems: The items displayed in the layout view.
    init(
        spacing: CGFloat = 5,
        layoutItems: Binding<[MenuBarLayoutItem]>
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
            RoundedRectangle(cornerRadius: 12)
                .fill(styleReader.style)
        }
        .shadow(radius: 10)
    }
}

struct PreviewMenuBarLayoutView: View {
    @State private var layoutItems = [
        MenuBarLayoutItem(image: badge("0")),
        MenuBarLayoutItem(image: badge("1")),
        MenuBarLayoutItem(image: badge("2")),
        MenuBarLayoutItem(image: badge("3")),
        MenuBarLayoutItem(image: badge("4")),
    ]

    var body: some View {
        MenuBarLayoutView(layoutItems: $layoutItems)
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
    let styleReader = MenuBarStyleReader()

    return VStack {
        PreviewMenuBarLayoutView()
        PreviewMenuBarLayoutView()
        PreviewMenuBarLayoutView()
    }
    .padding()
    .environmentObject(styleReader)
}
