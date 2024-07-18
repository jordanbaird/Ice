//
//  SectionedList.swift
//  Ice
//

import SwiftUI

struct SectionedList: View {
    private enum ScrollDirection {
        case up, down
    }

    @Binding var selection: ObjectIdentifier?
    @State private var itemFrames = [ObjectIdentifier: CGRect]()

    let spacing: CGFloat
    let items: [SectionedListItem]
    let padding: EdgeInsets

    private var nextSelectableItem: SectionedListItem? {
        guard
            let index = items.firstIndex(where: { $0.id == selection }),
            items.indices.contains(index + 1)
        else {
            return nil
        }
        return items[(index + 1)...].first { $0.isSelectable }
    }

    private var previousSelectableItem: SectionedListItem? {
        guard
            let index = items.firstIndex(where: { $0.id == selection }),
            items.indices.contains(index - 1)
        else {
            return nil
        }
        return items[...(index - 1)].last { $0.isSelectable }
    }

    init(
        selection: Binding<ObjectIdentifier?>,
        spacing: CGFloat = 0,
        padding: EdgeInsets = EdgeInsets(),
        items: [SectionedListItem]
    ) {
        self._selection = selection
        self.spacing = spacing
        self.padding = padding
        self.items = items
    }

    init(
        selection: Binding<ObjectIdentifier?>,
        spacing: CGFloat = 0,
        horizontalPadding: CGFloat = 0,
        verticalPadding: CGFloat = 0,
        items: [SectionedListItem]
    ) {
        self.init(
            selection: selection,
            spacing: spacing,
            padding: EdgeInsets(
                top: verticalPadding,
                leading: horizontalPadding,
                bottom: verticalPadding,
                trailing: horizontalPadding
            ),
            items: items
        )
    }

    var body: some View {
        ScrollViewReader { scrollView in
            GeometryReader { geometry in
                ScrollView {
                    scrollContent(scrollView: scrollView, geometry: geometry)
                }
                .padding(.top, padding.top)
                .padding(.bottom, padding.bottom)
                .scrollClipDisabled()
                .clipped()
            }
        }
    }

    @ViewBuilder
    private func scrollContent(scrollView: ScrollViewProxy, geometry: GeometryProxy) -> some View {
        VStack(spacing: spacing) {
            ForEach(items) { item in
                SectionedListItemView(
                    selection: $selection,
                    itemFrames: $itemFrames,
                    item: item
                )
                .id(item.id)
            }
        }
        .padding(.leading, padding.leading)
        .padding(.trailing, padding.trailing)
        .onKeyDown(key: .downArrow) {
            if let nextSelectableItem {
                selection = nextSelectableItem.id
            }
        }
        .onKeyDown(key: .upArrow) {
            if let previousSelectableItem {
                selection = previousSelectableItem.id
            }
        }
        .onKeyDown(key: .return) {
            items.first { $0.id == selection }?.action?()
        }
        .onChange(of: selection) {
            guard
                let selection,
                let direction = scrollDirection(for: selection, geometry: geometry)
            else {
                return
            }
            let anchor: UnitPoint = switch direction {
            case .up: .bottom
            case .down: .top
            }
            scrollView.scrollTo(selection, anchor: anchor)
        }
    }

    private func scrollDirection(for selection: ObjectIdentifier, geometry: GeometryProxy) -> ScrollDirection? {
        guard let selectionFrame = itemFrames[selection] else {
            return nil
        }
        let geometryFrame = geometry.frame(in: .global)
        if selectionFrame.maxY >= geometryFrame.maxY - padding.top {
            return .up
        }
        if selectionFrame.minY <= geometryFrame.minY + padding.bottom {
            return .down
        }
        return nil
    }
}

class SectionedListItem: Identifiable {
    let content: AnyView
    let isSelectable: Bool
    let action: (() -> Void)?

    init(content: AnyView, isSelectable: Bool, action: (() -> Void)?) {
        self.content = content
        self.isSelectable = isSelectable
        self.action = action
    }

    convenience init(isSelectable: Bool, action: (() -> Void)?, @ViewBuilder content: () -> some View) {
        self.init(content: AnyView(content()), isSelectable: isSelectable, action: action)
    }
}

class SectionedListHeaderItem: SectionedListItem {
    init(content: AnyView) {
        super.init(content: content, isSelectable: false, action: nil)
    }

    convenience init(@ViewBuilder content: () -> some View) {
        self.init(content: AnyView(content()))
    }
}

private struct SectionedListItemView: View {
    @Binding var selection: ObjectIdentifier?
    @Binding var itemFrames: [ObjectIdentifier: CGRect]
    @State private var isHovering = false

    let item: SectionedListItem

    var body: some View {
        ZStack {
            if item.isSelectable {
                itemBackground
            }
            item.content
        }
        .frame(minWidth: 22, minHeight: 22)
        .contentShape(Rectangle())
        .onHover { hovering in
            isHovering = hovering
        }
        .onTapGesture {
            selection = item.id
        }
        .onFrameChange(in: .global) { frame in
            itemFrames[item.id] = frame
        }
    }

    @ViewBuilder
    private var itemBackground: some View {
        VisualEffectView(material: .selection, blendingMode: .withinWindow)
            .clipShape(RoundedRectangle(cornerRadius: 5, style: .circular))
            .opacity(selection == item.id ? 0.5 : isHovering ? 0.25 : 0)
    }
}

#if DEBUG
private struct PreviewHelper: View {
    @State private var selection: ObjectIdentifier?

    var body: some View {
        SectionedList(
            selection: $selection,
            horizontalPadding: 10,
            verticalPadding: 10,
            items: [
                SectionedListHeaderItem(content: AnyView(Text("Section One"))),
                SectionedListItem(content: AnyView(Text("One")), isSelectable: true, action: nil),
                SectionedListItem(content: AnyView(Text("Two")), isSelectable: true, action: nil),
                SectionedListItem(content: AnyView(Text("Three")), isSelectable: true, action: nil),
                SectionedListItem(content: AnyView(Text("Four")), isSelectable: true, action: nil),
                SectionedListItem(content: AnyView(Text("Five")), isSelectable: true, action: nil),
                SectionedListHeaderItem(content: AnyView(Text("Section Two"))),
                SectionedListItem(content: AnyView(Text("Six")), isSelectable: true, action: nil),
                SectionedListItem(content: AnyView(Text("Seven")), isSelectable: true, action: nil),
                SectionedListItem(content: AnyView(Text("Eight")), isSelectable: true, action: nil),
                SectionedListItem(content: AnyView(Text("Nine")), isSelectable: true, action: nil),
                SectionedListItem(content: AnyView(Text("Ten")), isSelectable: true, action: nil),
            ]
        )
        .frame(width: 300, height: 100)
    }
}

#Preview {
    PreviewHelper()
}
#endif
